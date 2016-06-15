_ = require 'underscore'
Firebase = require 'firebase'
{makeObject, failHandler} = require './utils'
debug = require 'debug'
log = debug 'pegg:facebookImporter:log'
errorLog = debug 'pegg:facebookImporter:error'

class FacebookImporter
  start: (request, response) =>
    log "new user? :: #{JSON.stringify request.params}"
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
      .fail (error) ->
        error.stack = new Error().stack
        errorLog "24", error
        response.error error

  getFbFriends: =>
    query = new Parse.Query Parse.User
    query.equalTo 'objectId', @user.id
    query.first({ useMasterKey: true })
      .then (@user) =>
        authData = @user.get 'authData'
        token = authData.facebook.access_token
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
    firebase = new Firebase FIREBASE_DATABASE_URL
    firebase.authWithCustomToken FIREBASE_SECRET, (error, authData) =>
      if error?
        errorLog "Firebase login failed!", error
        throw error
      else
        log "logged into Firebase"
        fanOutsChannel = firebase.child 'fanOuts/tasks'
        # if @isNewUser
        peggFriendIds = _.map @peggFriends, (friend) -> friend.id
        fanOutsChannel.push
          userId: @user.id
          timestamp: @user.get('createdAt').valueOf()
          friends: peggFriendIds

  updateUserFriends: =>
    privatesQuery = new Parse.Query 'UserPrivates'
    log 'SAVING USER PRIVATES: ' + @user.id
    privatesQuery.equalTo 'user', @user
    privatesQuery.first({ useMasterKey: true })
      .then (res) =>
        res.set 'friends', fbIds: @friendsArray
        res.save(null, { useMasterKey: true })

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
          fbFriendsRole.save(null, { useMasterKey: true })
            .then =>
              promise.resolve() # updateBackwardPermissions needs fbFriendsRole to exist, but can continue without the rest of this
              parentRoleName = "#{@user.id}_Friends"
              query.equalTo "name", parentRoleName
              query.find({ useMasterKey: true })
                .then (results) =>
                  if results.length is 0
                    # create a role that can see user's cards
                    parentACL = new Parse.ACL()
                    parentRole = new Parse.Role parentRoleName, parentACL
                    parentRole.getRoles().add fbFriendsRole
                    parentRole.save(null, { useMasterKey: true })
                      .fail (error) => errorLog "100", error
                    # add that role to the user record
                    currUserAcl = new Parse.ACL @user
                    currUserAcl.setRoleReadAccess "#{@user.id}_Friends", true
                    @user.set 'ACL', currUserAcl
                    @user.save(null, { useMasterKey: true })
                      .fail (error) => errorLog "100", error
                  else
                    parentRole = results[0]
                    parentRole.getRoles().add fbFriendsRole
                    parentRole.save(null, { useMasterKey: true })
                      .fail (error) => errorLog "100", error
            .fail (error) =>
              errorLog "100", error
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
              errorLog "112", error
              promise.reject error
          # add current friends
          if @peggFriends.length > 0
            relation.add @peggFriends
          log "updating user role: ", fbFriendsRole, relation
          fbFriendsRole.save(null, { useMasterKey: true })
          promise.resolve()
        else
          promise.reject "Something went wrong. There should only be one role called #{fbFriendsRoleName}, but we have #{results.length} of them."

      .fail (error) =>
        errorLog "123", error
        promise.reject error
    promise

  updateBackwardPermissions: =>
    friendRoles = []
    # ADD user to friends' roles
    for friend in @peggFriends
      friendRoles.push "#{friend.id}_FacebookFriends"
    log friendRoles

    query = new Parse.Query Parse.Role
    query.containedIn 'name', friendRoles
    query.find({ useMasterKey: true })
      .then (results) =>
        for fbFriendsRole in results
          relation = fbFriendsRole.getUsers()
          relation.add @user
          log "updating friend role: ", fbFriendsRole, relation
          fbFriendsRole.save(null, { useMasterKey: true })

  finish: =>
    message = "Updated #{@user.get 'first_name'}'s friends from Facebook (Pegg user id #{@user.id})"
    @response.success message

module.exports = new FacebookImporter
