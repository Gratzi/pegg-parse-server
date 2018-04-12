_ = require 'underscore'
sha1 = require 'sha1'
sendInBlue = require '../lib/sendInBlue'
slack = require '../lib/slack'
Firebase = require '../lib/firebase'
twilio = require '../lib/twilio'
debug = require 'debug'
log = debug 'pegg:worker:log'

###################################
######### CLOUD FUNCTIONS #########

Parse.Cloud.define "getFirebaseToken", (request, response) ->
  Firebase.getToken userId: request.user.id
  .then (token) =>
    response.success token
  .fail (err) =>
    response.error err

Parse.Cloud.define "updateEmail", (request, response) ->
  email = request.params.newEmail
  firstName = request.params.firstName
  lastName = request.params.lastName
  sendInBlue.createOrUpdate {email, firstName, lastName}
  .then (res) =>
    sendInBlue.delete email: request.params.oldEmail
  .then (res) =>
    response.success "Updated email address successfully"
  .fail (err) =>
    response.error err

Parse.Cloud.define "error", (request, response) ->
  if request.params?
    user = request.params.user or { name: "Unknown user", id: "Unknown ID" }
    error = request.params.error or { stack: "Unknown error" }
    userAgent = request.params.userAgent or ''
    slack.clientError error, user, userAgent
    .then (res) =>
      response.success res
    .fail (err) =>
      response.error err

Parse.Cloud.define "feedback", (request, response) ->
  if request.params?
    user =
      id: request.params.id
      email: request.params.email
      name: request.params.name
    userAgent = request.params.userAgent or ''
    context = request.params.context or ''
    feedback = request.params.feedback or ''
    slack.userFeedback user, userAgent, context, feedback
    .then (res) =>
      response.success res
    .fail (err) =>
      response.error err

Parse.Cloud.define "requestFriend", (request, response) ->
  user = request.user
  friend = new Parse.User
  friend.id = request.params.friendId
  friendPublics = new Parse.Object 'UserPublics'
  friendPublics.id = request.params.friendPublicsId
  userPublics = new Parse.Object 'UserPublics'
  userPublics.id = request.params.userPublicsId
  userName = request.params.userName
  saveFriendRequest user, friend, friendPublics, userPublics
  .then (res) =>
    response.success res
    Firebase.sendToInbox type: 'friendRequest', userId: user.id, friendId: friend.id
    Firebase.sendPush
      title: "#{userName} sent you a friend request."
      message: "Confirm the request to start pegging them!"
      userId: user.id
      friendId: friend.id
      type: 'friendRequest'
  .fail (err) =>
    response.error err

Parse.Cloud.define "confirmRequest", (request, response) ->
  user = request.user
  friend = new Parse.User
  friend.id = request.params.friendId
  userName = request.params.userName
  # delete the request the other user made
  deleteFriendRequest friend, user
  .then (res) =>
    if res?
      createFriendship user.id, friend.id
      .then =>
        Firebase.sendToInbox type: 'friendsUpdate', userId: user.id, friendId: friend.id
        Firebase.sendToInbox type: 'friendsUpdate', userId: friend.id, friendId: user.id
        Firebase.sendPush
          title: "#{userName} confirmed your friend request!"
          message: "Start pegging them."
          userId: user.id
          friendId: friend.id
      response.success res
    else
      response.error res

Parse.Cloud.define "addFriend", (request, response) ->
  userId = request.user.id
  friendId = request.params.friendId
  userName = request.params.userName
  createFriendship userId, friendId
  .then =>
    Firebase.sendToInbox type: 'friendsUpdate', userId: userId, friendId: friendId
    Firebase.sendToInbox type: 'friendsUpdate', userId: friendId, friendId: userId
    Firebase.sendPush
      title: "You and #{userName} are now friends!"
      message: "Start pegging them."
      userId: userId
      friendId: friendId
    response.success()
  .fail (err) =>
    response.error err

Parse.Cloud.define "removeFriend", (request, response) ->
  userId = request.user.id
  friendId = request.params.friendId
  deleteFriendship userId, friendId

Parse.Cloud.define "createCard", (request, response) ->
  # console.log 'CARD: ', JSON.stringify request.params.card
  createCard request.user, request.params.card
  .then (res) =>
    response.success res
  .fail (error) =>
    response.error error

Parse.Cloud.define "sendVerifyCode", (request, response) ->
  phoneNumber = request.params.phoneNumber
  if phoneNumber?
    code = Math.floor(Math.random() * 90000) + 10000 # random 6 digit code
    Firebase.saveVerifyCode { phoneNumber, code }
    .then =>
      twilio.sendSMS phoneNumber, "Pegg Code: #{code}. Get your pegg on!"
    .then (message) =>
      response.success message.sid
    .fail (error) =>
      response.error error
  else
    response.error 'must submit a phone number'

Parse.Cloud.define "checkVerifyCode", (request, response) ->
  phoneNumber = request.params.phoneNumber
  code = parseInt request.params.code
  if phoneNumber? and code?
    Firebase.getVerifyCode { phoneNumber }
    .then (result) =>
      log "code from firebase: #{result} vs. request #{code}"
      if result? and result is code
        # Verified!
        password = generatePassword 15
        username = sha1 phoneNumber
        # if user already exists then resetPassword else create user
        userQuery = new Parse.Query 'User'
        userQuery.equalTo 'username', username
        userQuery.first({ useMasterKey: true })
        .then (user) =>
          if user?
            user.setPassword password
            user.save(null, { useMasterKey: true })
          else
            Parse.User.signUp(username, password, {
              isActive: true
            }).then (user) =>
              roleName = "#{user.id}_Friends"
              console.log "creating role", roleName
              roleAcl = new Parse.ACL()
              role = new Parse.Role roleName, roleAcl
              role.save(null, { useMasterKey: true })
              userAcl = new Parse.ACL user
              userAcl.setPublicReadAccess false
              userAcl.setPublicWriteAccess false
              userAcl.setRoleReadAccess "#{user.id}_Friends", true
              user.set 'ACL', userAcl
              user.save(null, { useMasterKey: true })
        .then (user) =>
          response.success { password }
        .fail (error) =>
          log.error error
          response.error error
      else
        response.error 'incorrect code'
    .fail (error) =>
      log.error error
      response.error error
  else
    response.error 'must submit a phoneNumber and Code'


###########################################
######### AFTER SAVE, DELETE, ETC #########

Parse.Cloud.afterSave 'Pegg', (request) ->
  user = request.user
  if !request.object.existed()
    pref = request.object.get 'pref'
    card = request.object.get 'card'
    peggee = request.object.get 'peggee'
    guess = request.object.get 'guess'
    answer = request.object.get 'answer'
    question = request.object.get 'question'
    failCount = request.object.get 'failCount'
    deck = request.object.get 'deck'
    # Correct! Save stats and update Bestie Score
    if guess.id is answer.id
      updatePrefStats { user, card, pref, guess, failCount, correctAnswer: true }
      updateBestieScore user, peggee, failCount, deck
    else
      updatePrefStats { user, card, pref, guess, failCount, correctAnswer: false }

Parse.Cloud.afterSave 'Pref', (request) ->
  pref = request.object
  user = request.user
  card = request.object.get 'card'
  author = request.object.get 'author'
  answer = request.object.get 'answer'
  deck = request.object.get 'deck'
  question = request.object.get 'question'
  if !pref.existed() # if new object
    updateCardHasPreffed user, card # updates hasPreffed on Card
    incrementChoiceCount answer.id, 'prefCount' # what's the most popular preference?
    if author?
      incrementStars author.id

Parse.Cloud.afterSave 'UserPrivates', (request) ->
# can't use afterSave Parse.User because on new user creation two saves happen, the first without any user details
  userPrivates = request.object
  if !userPrivates.existed() # if new object
    email = userPrivates.get 'email'
    firstName = userPrivates.get 'firstName'
    lastName = userPrivates.get 'lastName'
    if email?
      console.log "subscribing to SendInBlue:", JSON.stringify {email, firstName, lastName}
      sendInBlue.createOrUpdate {email, firstName, lastName}
      .then (res) =>
        console.log res

###########################
######### HELPERS #########
# credit: https://gist.github.com/jacobbuck/4247179
generatePassword = (length) ->
  password = ''
  character = undefined
  while length > password.length
    if password.indexOf(character = String.fromCharCode(Math.floor(Math.random() * 94) + 33), Math.floor(password.length / 94) * 94) < 0
      password += character
  password


# TODO: set class level ACL on Card to Public Read only
createCard = (user, card) ->
  cardPromise = new Parse.Promise
  newCardAcl = new Parse.ACL user
  newCardAcl.setRoleReadAccess "#{user.id}_Friends", true
  newCard = new Parse.Object 'Card'
  newCard.set 'question', card.question
  newCard.set 'createdBy', user
  newCard.set 'disabled', true
  newCard.set 'publishDate', new Date
  newCard.set 'deck', 'Friends'
  newCard.set 'ACL', newCardAcl
  newCard.save(null, { useMasterKey: true })
  .then (newCard) =>
    saved = for choice in card.choices
      saveChoice user.id, newCard.id, choice
    Parse.Promise.when saved
    .then (choices...) =>
      cardChoices = _.indexBy choices[0], 'id'
      finishCardCreation newCard, cardChoices

saveChoice = (userId, cardId, answer) ->
  choicePromise = new Parse.Promise
  createdBy = new Parse.User
  createdBy.set 'id', userId
  card = new Parse.Object 'Card'
  card.set 'id', cardId
  acl = new Parse.ACL createdBy
  acl.setPublicReadAccess false
  choice = new Parse.Object 'Choice'
  choice.set 'text', answer.text
  choice.set 'image', answer.image
  choice.set 'card', card
  choice.set 'createdBy', createdBy
  choice.set 'ACL', acl
  choice.save(null, { useMasterKey: true })
  .then (choice) =>
    choicePromise.resolve
      id: choice.id
      cardId: choice.get('card')?.id
      text: choice.get('text')
      image: choice.get('image')
  .fail (error) =>
    console.log "ERROR:   ", error
    choicePromise.reject error
  choicePromise

finishCardCreation = (card, choices) ->
  card.set 'choices', choices
  card.set 'disabled', false
  card.save(null, { useMasterKey: true })

updatePrefStats = ({ user, card, pref, guess, failCount, correctAnswer }) ->
  console.error "updatePrefStats:", pref
  token = user.getSessionToken()
  pref.fetch({sessionToken: token})
  .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"
  .then (pref) =>
    console.log "updatePrefStats: fetched pref -- #{JSON.stringify pref}"
    choices = pref.get('choices')
    firstTry = failCount is 0
    if correctAnswer
      # UPDATE Pref with userId in hasPegged array
      pref.addUnique 'hasPegged', user.id
    if firstTry
      if choices?
        choices[guess.id].peggCount++
        pref.set 'choices', choices
      else
        # TODO: Sometimes choices don't get populated on Pref creation, not sure why
        console.log "ERROR: aaaaarg choices should exist... refetching..."
        getChoices(card)
        .then (choices) =>
          choices[guess.id].peggCount++
          pref.set 'choices', choices
          pref.save(null, { useMasterKey: true })
    if correctAnswer or firstTry
      pref.save(null, { useMasterKey: true })
      .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"
      .then => console.log "updatePrefStats: success -- #{JSON.stringify pref}"

createFriendship = (userId, friendId) ->
  Parse.Promise.when(
    addFriendToRole("#{friendId}_Friends", userId)
    addFriendToRole("#{userId}_Friends", friendId)
  )

deleteFriendship = (userId, friendId) ->
  Parse.Promise.when(
    removeFriendFromRole("#{friendId}_Friends", userId)
    removeFriendFromRole("#{userId}_Friends", friendId)
  )

getFriendRequest = (user, friend) ->
  requestQuery = new Parse.Query 'Request'
  requestQuery.equalTo 'friend', friend
  requestQuery.equalTo 'user', user
  requestQuery.first({ useMasterKey: true })

deleteFriendRequest = (user, friend) ->
  getFriendRequest user, friend
  .then (res) =>
    console.log "getFriend Result: ", res
    if res? then res.destroy({ useMasterKey: true })

saveFriendRequest = (user, friend, friendPublics, userPublics) ->
  getFriendRequest user, friend
  .then (res) ->
    unless res?
      newRequestACL = new Parse.ACL()
      newRequestACL.setReadAccess friend.id, true
      newRequestACL.setReadAccess user.id, true
      newRequest = new Parse.Object 'Request'
      newRequest.set 'user', user
      newRequest.set 'friend', friend
      newRequest.set 'friendPublics', friendPublics
      newRequest.set 'userPublics', userPublics
      newRequest.set 'ACL', newRequestACL
      newRequest.save(null, { useMasterKey: true })
    else
      promise = new Parse.Promise
      return promise.reject()

incrementStars = (authorId) ->
  userQuery = new Parse.Query 'User'
  userQuery.equalTo 'objectId', authorId
  userQuery.first({ useMasterKey: true })
  .then (user) =>
    user.increment 'starCount'
    user.save(null, { useMasterKey: true })
  .then =>
    console.log "incrementStars success: #{authorId}"
  .fail (error) =>
    console.error 'incrementStars fail', error


updateBestieScore = (user, peggee, failCount, deck) ->
  token = user.getSessionToken()
  bestieQuery = new Parse.Query 'Bestie'
  bestieQuery.equalTo 'friend', peggee
  bestieQuery.equalTo 'user', user
  bestieQuery.first({ sessionToken: token })
  .then (bestie) ->
    if bestie?
      peggCounts = bestie.get('peggCounts') or {}
      if peggCounts[deck]? then peggCounts[deck]++ else peggCounts[deck] = 1
      bestie.set 'peggCounts', peggCounts
      bestie.set 'lastDeck', deck
      bestie.increment 'failCount', failCount
      bestie.increment 'peggCount'
      score = Math.round(( 1 - bestie.get('failCount') / (bestie.get('peggCount') + bestie.get('failCount'))) * 100)
      bestie.set 'score', score
      bestie.save(null, { useMasterKey: true })
        .then => console.log "updateBestieScore: success -- #{JSON.stringify bestie}"
        .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify bestie}", err
    else
      newBestieAcl = new Parse.ACL()
      newBestieAcl.setRoleReadAccess "#{user.id}_Friends", true
      newBestieAcl.setRoleReadAccess "#{peggee.id}_Friends", true
      newBestieAcl.setReadAccess user.id, true
      newBestie = new Parse.Object 'Bestie'
      newBestie.set 'failCount', failCount
      newBestie.set 'peggCount', 1
      newBestie.set 'friend', peggee
      newBestie.set 'user', user
      newBestie.set 'lastDeck', deck
      peggCounts = {}
      if peggCounts[deck]? then peggCounts[deck]++ else peggCounts[deck] = 1
      newBestie.set 'peggCounts', peggCounts
      score = Math.round(( 1 - newBestie.get('failCount') / (newBestie.get('peggCount') + newBestie.get('failCount'))) * 100)
      newBestie.set 'score', score
      newBestie.set 'ACL', newBestieAcl
      newBestie.save(null, { useMasterKey: true })
      .then => console.log "updateBestieScore: success"
      .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify newBestie}", err

updateCardHasPreffed = (user, card) ->
  token = user.getSessionToken()
  card.fetch({sessionToken: token})
  .then (card) =>
    if card.get('hasPreffed') is undefined
      card.set 'hasPreffed', []
    card.addUnique 'hasPreffed', user.id
    card.save(null, { useMasterKey: true })
      .fail (error) ->
        console.log 'hasPreffed failed', error
      .then =>
        console.log "hasPreffed saved: #{card.id}"

addFriendToRole = (roleName, friendId) ->
  promise = new Parse.Promise()
  query = new Parse.Query Parse.Role
  query.equalTo "name", roleName
  query.first({ useMasterKey: true })
  .then (role) =>
    if role?
      relation = role.getUsers()
      query = new Parse.Query Parse.User
      query.equalTo "objectId", friendId
      query.first({ useMasterKey: true })
      .then (friend) =>
        if friend?
          relation.add friend
          role.save(null, { useMasterKey: true })
        else
          promise.reject 'friendId not found.'
      .then =>
        promise.resolve()
      .fail (error) =>
        console.error "75", error
        promise.reject error
    else
      promise.reject "role missing: #{roleName}"
  .fail (error) =>
    console.error "79", error
    promise.reject error
  promise

removeFriendFromRole = (roleName, friendId) ->
  promise = new Parse.Promise()
  query = new Parse.Query Parse.Role
  query.equalTo "name", roleName
  query.first({ useMasterKey: true })
  .then (role) =>
    if role?
      relation = role.getUsers()
      query = new Parse.Query Parse.User
      query.equalTo "objectId", friendId
      query.first({ useMasterKey: true })
      .then (friend) =>
        relation.remove friend
        role.save(null, { useMasterKey: true })
      .then =>
        promise.resolve()
      .fail (error) =>
        console.error "75", error
        promise.reject error
    else
      promise.reject "role missing: #{roleName}"
  .fail (error) =>
    console.error "79", error
    promise.reject error
  promise

# returns {<id>: {text: 'hey', peggCount: 0}, <id2>: ...}
# requires useMasterKey
getChoices = (card) ->
  choiceQuery = new Parse.Query 'Card'
  choiceQuery.equalTo 'objectId', card.id
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        choices = result.get('choices')
        for own id, choice of choices
          choice.peggCount = 0
        return choices
      else
        return null

incrementChoiceCount = (choiceId, fieldName) ->
  choiceQuery = new Parse.Query 'Choice'
  choiceQuery.equalTo 'objectId', choiceId
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, 1
        result.save(null, { useMasterKey: true })
