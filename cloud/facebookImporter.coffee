_ = require 'underscore'
Firebase = require '../lib/firebase'
debug = require 'debug'
log = debug 'pegg:facebookImporter:log'
errorLog = debug 'pegg:facebookImporter:error'

class FacebookImporter
  start: (@user) =>
    @getFbFriends()
    .then @getPeggUsersFromFbFriends
    .then @updateForwardPermissions
    .then @updateBackwardPermissions
    .then @sendFirebaseNotifications

  getFbFriends: =>
    log "getFbFriends"
    query = new Parse.Query Parse.User
    query.equalTo 'objectId', @user.id
    query.first({ useMasterKey: true })
    .then (@user) =>
      authData = @user.get 'authData'
      if authData?.facebook?.access_token
        url = "https://graph.facebook.com/me/friends?fields=id&access_token=" + authData.facebook.access_token
        @_getFbFriends url, []

  _getFbFriends: (url, fbFriends) =>
#    log "_getFbFriends", url, fbFriends
    Parse.Cloud.httpRequest url: url
    .then (results) =>
      fbFriends = fbFriends.concat(results.data.data)
      if results.data.paging and results.data.paging.next
        @_getFbFriends results.data.paging.next, fbFriends
      else
        fbFriends

  getPeggUsersFromFbFriends: (fbFriends) =>
    log "getPeggUsersFromFbFriends", fbFriends
    fbFriendsArray = _.map fbFriends, (friend) => friend.id
    @_updateUserFriends fbFriendsArray
    query = new Parse.Query Parse.User
    query.containedIn "facebook_id", fbFriendsArray
    query.find({ useMasterKey: true })

  _updateUserFriends: (fbFriendsArray) =>
#    log "_updateUserFriends", fbFriendsArray
    privatesQuery = new Parse.Query 'UserPrivates'
    privatesQuery.equalTo 'user', @user
    privatesQuery.first({ useMasterKey: true })
    .then (res) =>
      res.set 'friends', fbIds: fbFriendsArray
      res.save(null, { useMasterKey: true })

  updateForwardPermissions: (peggFriends) =>
    log "updateForwardPermissions", peggFriends
    promise = new Parse.Promise()
    @_getFacebookFriendsRole()
    .then (fbFriendsRole) =>
      unless fbFriendsRole?
        @_createFacebookFriendsRole peggFriends
        .then (fbFriendsRole) =>
          @_createParentFriendRole fbFriendsRole
          # updateBackwardPermissions needs _FacebookFriends role to exist, but can continue without the parent role
          promise.resolve peggFriends
        .fail (error) =>
          errorLog "100", error
          promise.reject error
      else
        @_updateFacebookFriendsRole fbFriendsRole, peggFriends
        .then ->
          promise.resolve peggFriends
        .fail (error) =>
          errorLog "100", error
          promise.reject error
    promise

  _getFacebookFriendsRole: =>
#    log "_getFacebookFriendsRole"
    query = new Parse.Query Parse.Role
    fbFriendsRoleName = "#{@user.id}_FacebookFriends"
    query.equalTo "name", fbFriendsRoleName
    query.first({ useMasterKey: true })

  _createFacebookFriendsRole: (peggFriends) =>
    # create a role that lists user's friends from Facebook
#    log "_createFacebookFriendsRole", peggFriends
    fbFriendsRoleName = "#{@user.id}_FacebookFriends"
    fbFriendsRole = new Parse.Role fbFriendsRoleName, new Parse.ACL()
    if peggFriends.length > 0
      fbFriendsRole.getUsers().add peggFriends
    fbFriendsRole.save(null, { useMasterKey: true })

  _createParentFriendRole: (fbFriendsRole) =>
#    log "_createParentFriendRole", fbFriendsRole
    parentRoleName = "#{@user.id}_Friends"
    query = new Parse.Query Parse.Role
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
      else
        parentRole = results[0]
        parentRole.getRoles().add fbFriendsRole
        parentRole.save(null, { useMasterKey: true })

  _updateFacebookFriendsRole: (fbFriendsRole, peggFriends) =>
#    log "_updateFacebookFriendsRole", fbFriendsRole, peggFriends
    relation = fbFriendsRole.getUsers()
    query = relation.query()
    query.find({ useMasterKey: true })
    .then (friends) =>
      # dump old friends
      relation.remove friends
      # add current friends
      if peggFriends.length > 0
        relation.add peggFriends
      fbFriendsRole.save(null, { useMasterKey: true })

  updateBackwardPermissions: (peggFriends) =>
    log "updateBackwardPermissions", peggFriends
    promise = new Parse.Promise()
    if peggFriends.length > 0
      friendRoles = []
      # ADD user to friends' roles
      for friend in peggFriends
        friendRoles.push "#{friend.id}_FacebookFriends"
#      log friendRoles
      query = new Parse.Query Parse.Role
      query.containedIn 'name', friendRoles
      query.find({ useMasterKey: true })
      .then (results) =>
        for fbFriendsRole in results
          relation = fbFriendsRole.getUsers()
          relation.add @user
#          log "updating friend role: ", fbFriendsRole, relation
          fbFriendsRole.save(null, { useMasterKey: true })
        promise.resolve peggFriends
      .fail (error) =>
        errorLog "100", error
        promise.reject error
    promise

  sendFirebaseNotifications: (peggFriends) =>
    log "sendFirebaseNotifications", peggFriends
    promise = new Parse.Promise()
    if peggFriends.length > 0
      Firebase.fanOut
        userId: @user.id
        friendIds: _.map peggFriends, (friend) -> friend.id
        timestamp: @user.get('createdAt').valueOf()
    promise.resolve()

module.exports = FacebookImporter
