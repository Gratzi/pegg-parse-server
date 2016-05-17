_ = require 'underscore'
firebase = require './firebase'
{makeObject, failHandler} = require './utils'

class FacebookImporter
  start: (request, response) =>
    console.log "new user? :: #{JSON.stringify request.params}"
    @isNewUser = request.params.newUser
    @response = response
    @user = request.user

    # XXX this shouldn't be necessary if we call functions with useMasterKey: true
    # It's a bug: https://developers.facebook.com/bugs/306759706140811/
    # It's fixed in the latest JS SDK version
    @getFbFriends()
      .then @getPeggUsersFromFbFriends
      .then @updateUserFriends
      .then @updateForwardPermissions
      .then @updateBackwardPermissions
      .then @sendFirebaseNotifications
      .then @finish
      .fail (error) -> response.error error

  getFbFriends: =>
    query = new Parse.Query Parse.User
    query.equalTo 'objectId', @user.id
    query.find({ useMasterKey: true })
      .then (@user) =>
        console.log "33333333333333333333333333333333333", @user, "22222222222222222222222222222222"
        token = @user.authData.facebook.access_token
        url = "https://graph.facebook.com/me/friends?fields=id&access_token=" + token
        @_getFbFriends url, []

  _getFbFriends: (url, friends) =>
    Parse.Cloud.httpRequest url: url
      .then (results) =>
        friends = friends.concat(results.data.data)
        if results.data.paging and results.data.paging.next
          @_getFbFriends results.data.paging.next, friends
        else
          @fbFriends = friends

  getPeggUsersFromFbFriends: =>
    @friendsArray = _.map @fbFriends, (friend) => friend.id
    query = new Parse.Query Parse.User
    query.containedIn "facebook_id", @friendsArray
    query.find({ useMasterKey: true })
      .then (res) =>
        @peggFriends = res

  sendFirebaseNotifications: =>
    if @isNewUser
      peggFriendIds = _.map @peggFriends, (friend) -> friend.id
      firebase.saveNewUser @user.id, peggFriendIds, @user.createdAt

  updateUserFriends: =>
    privatesQuery = new Parse.Query 'UserPrivates'
    console.log 'SAVING USER PRIVATES: ' + @user.id
    privatesQuery.equalTo 'user', @user
    privatesQuery.first({ useMasterKey: true })
      .then (res) =>
        res.set 'friends', fbIds: @friendsArray
        res.save({ useMasterKey: true })

  updateForwardPermissions: =>
    # TODO: refactor this function, it is a MONSTOR
    promise = new Parse.Promise()

    # ADD friends to user's Role
    query = new Parse.Query Parse.Role
    fbFriendsRoleName = "#{@user.id}_FacebookFriends"
    query.equalTo "name", fbFriendsRoleName
    query.find({ useMasterKey: true })
      .then (results) =>
        if results.length is 0
          # create a role that lists user's friends from Facebook
          fbFriendsRole = new Parse.Role fbFriendsRoleName, new Parse.ACL()
          if @peggFriends.length > 0
            fbFriendsRole.getUsers().add @peggFriends
          fbFriendsRole.save({ useMasterKey: true })
            .then =>
              # create a role that can see user's cards
              parentRoleName = "#{@user.id}_Friends"
              parentACL = new Parse.ACL()
              parentRole = new Parse.Role parentRoleName, parentACL
              parentRole.getRoles().add fbFriendsRole
              parentRole.save({ useMasterKey: true })

              # add that role to the user record
              currUserAcl = new Parse.ACL @user
              currUserAcl.setRoleReadAccess "#{@user.id}_Friends", true
              @user.set 'ACL', currUserAcl
              @user.save({ useMasterKey: true })

              promise.resolve()
            .fail (error) =>
              promise.reject error
        else if results.length is 1
          # role exists, just need to update friends list
          fbFriendsRole = results[0]
          relation = fbFriendsRole.getUsers()
          # dump old friends
          query = relation.query()
          query.find({ useMasterKey: true })
            .then (friends) =>
              relation.remove friends
            .fail (error) =>
              promise.reject error
          # add current friends
          if @peggFriends.length > 0
            relation.add @peggFriends
          fbFriendsRole.save({ useMasterKey: true })
          promise.resolve()
        else
          promise.reject "Something went wrong. There should only be one role called #{fbFriendsRoleName}, but we have #{results.length} of them."

      .fail (error) =>
        promise.reject error
    promise

  updateBackwardPermissions: =>
    friendRoles = []
    # ADD user to friends' roles
    for friend in @peggFriends
      friendRoles.push "#{friend.id}_FacebookFriends"
    console.log friendRoles

    query = new Parse.Query Parse.Role
    query.containedIn 'name', friendRoles
    query.find({ useMasterKey: true })
      .then (results) =>
        for fbFriendsRole in results
          relation = fbFriendsRole.getUsers()
          friend = new Parse.Object 'User'
          friend.set 'id', @user.id
          relation.add friend
          fbFriendsRole.save({ useMasterKey: true })

  finish: =>
    message = "Updated #{@user.attributes.first_name}'s friends from Facebook (Pegg user id #{@user.id})"
    @response.success message

module.exports = new FacebookImporter
