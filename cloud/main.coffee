_ = require 'underscore'
sha1 = require 'sha1'
facebookImporter = require './facebookImporter'
mailChimp = require './mailchimp'
{makeObject, failHandler} = require './utils'
FirebaseTokenGenerator = require 'firebase-token-generator'

######### CLOUD FUNCTIONS #########

Parse.Cloud.define "importFriends", facebookImporter.start

Parse.Cloud.define "getFirebaseToken", (request, response) ->
  FIREBASE_SECRET = process.env.FIREBASE_SECRET or throw new Error "cannot have an empty FIREBASE_SECRET"
  tokenGenerator = new FirebaseTokenGenerator FIREBASE_SECRET
  token = tokenGenerator.createToken {uid: request.user.id}, {expires: 2272147200}
  response.success token

######### AFTER SAVE, DELETE, ETC #########

Parse.Cloud.afterSave '_User', (request) ->
  user = request.object
  facebookId = user.get 'facebook_id'
  if !user.existed() and !facebookId?
    createUserFriendsRole user

createUserFriendsRole: (user) ->
  roleName "#{user.id}_Friends"
  roleAcl = new Parse.ACL()
  role = new Parse.Role roleName, roleAcl
  role.save(null, { useMasterKey: true })

Parse.Cloud.afterSave 'Pegg', (request) ->
  user = request.user

  if !request.object.existed()
    pref = request.object.get 'pref'
    card = request.object.get 'card'
    peggee = request.object.get 'peggee'
    guess = request.object.get 'guess'
    answer = request.object.get 'answer'
    question = request.object.get 'question'
    tryCount = request.object.get 'tryCount'

    # Calculate points
    points = 10 - 3 * tryCount

    # Correct! Save peggerPoints and activity
    if guess.id is answer.id
      updatePrefStats user, card, pref, guess, points, true
      # updateUserPeggedCards user, points
      updateBestieScore user, peggee, points
    else
      updatePrefStats user, card, pref, guess, points, false

Parse.Cloud.afterSave 'Pref', (request) ->
  pref = request.object
  user = request.user
  card = request.object.get 'card'
  answer = request.object.get 'answer'
  mood = request.object.get 'mood'
  question = request.object.get 'question'
  updateCardHasPreffed user, card # updates hasPreffed on Card
  if !pref.existed() # if new object
    incrementChoiceCount answer.id, 'prefCount' # what's the most popular preference?
    # updateUserPrefCount user

Parse.Cloud.afterSave 'Flag', (request) ->
  cardId = request.object.get('card').id
  incrementCardCount cardId, 'flags'

Parse.Cloud.afterSave 'UserPrivates', (request) ->
# can't use afterSave Parse.User because on new user creation two saves happen, the first without any user details
  userPrivates = request.object
  if !userPrivates.existed() # if new object
    email = userPrivates.get 'email'
    firstName = userPrivates.get 'firstName'
    lastName = userPrivates.get 'lastName'
    console.log "subscribing to MailChimp:", JSON.stringify {email, firstName, lastName}
    mailChimp.subscribe {email, firstName, lastName}

######### HELPER #########

# note that this will not work if useMasterKey has been enabled within current request
#getUserFriends = ->
#  cardQuery = new Parse.Query 'User'
#  cardQuery.notEqualTo 'objectId', Parse.User.current().id
#  cardQuery.find()
#    .then (friends) =>
#      _.map friends, (friend) => friend.id

#getCardChoices = (card) ->
#  cardQuery = new Parse.Query 'Card'
#  cardQuery.equalTo 'objectId', card.id
#  cardQuery.first()
#    .then (result) =>
#      result.get('choices') or {}

# returns {<id>: {text: 'hey', peggCount: 0, peggPoints: 0}, <id2>: ...}
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
          choice.peggPoints = 0
        return choices
      else
        return null

incrementCardCount = (cardId, fieldName) ->
  cardQuery = new Parse.Query 'Card'
  cardQuery.equalTo 'objectId', cardId
  cardQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, 1
        result.save({ useMasterKey: true })

decrementCardCount = (cardId, fieldName) ->
  cardQuery = new Parse.Query 'Card'
  cardQuery.equalTo 'objectId', cardId
  cardQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, -1
        result.save({ useMasterKey: true })

incrementChoiceCount = (choiceId, fieldName) ->
  choiceQuery = new Parse.Query 'Choice'
  choiceQuery.equalTo 'objectId', choiceId
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, 1
        result.save({ useMasterKey: true })

decrementChoiceCount = (choiceId, fieldName) ->
  choiceQuery = new Parse.Query 'Choice'
  choiceQuery.equalTo 'objectId', choiceId
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, -1
        result.save({ useMasterKey: true })

# updateUserPeggedCards = (user, points) ->
#   console.log "updateUserPeggedCards: for user -- #{JSON.stringify user} -- points #{points}"
#   user.increment 'pegged_cards'
#   user.increment 'pegg_score', points
#   user.save()

# updateUserPrefCount = (user) ->
#   console.log "updateUserPrefCount: for user -- #{JSON.stringify user}"
#   user.increment 'pref_count'
#   user.save()

updatePrefStats = (user, card, pref, guess, points, correctAnswer) ->
  token = user.getSessionToken()
  pref.fetch({sessionToken: token})
    .then (pref) =>
      console.log "updatePrefStats: fetched pref -- #{JSON.stringify pref}"
      choices = pref.get('choices')
      if choices?
        choices[guess.id].peggCount += 1
        choices[guess.id].peggPoints += points
        pref.set 'choices', choices
      else
        # Sometimes choices don't get populated on Pref creation, not sure why
        console.log "ERROR: aaaaarg choices should exist... refetching..."
        getChoices(card)
          .then (choices) =>
            choices[guess.id].peggCount += 1
            choices[guess.id].peggPoints += points
            pref.set 'choices', choices
            pref.save({ useMasterKey: true })
      if correctAnswer
      # UPDATE Pref row(s) with userId in hasPegged array
        pref.addUnique 'hasPegged', user.id
      pref.save({ useMasterKey: true })
        .then => console.log "updatePrefStats: success -- #{JSON.stringify pref}"
        .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"

updateBestieScore = (user, peggee, points) ->
  token = user.getSessionToken()
  bestieQuery = new Parse.Query 'Bestie'
  bestieQuery.equalTo 'friend', peggee
  bestieQuery.equalTo 'user', user
  bestieQuery.first({ sessionToken: token })
    .then (bestie) ->
      if bestie?
        bestie.increment 'score', points
        bestie.increment 'cards'
        currLevel = bestie.get('level') or 1
        score = bestie.get 'score'
        if score >= currLevel * 21 # 21 = average points (7) * 3 cards
          bestie.set 'level', currLevel + 1
        bestie.save({ useMasterKey: true })
          .then => console.log "updateBestieScore: success -- #{JSON.stringify bestie}"
          .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify bestie}"
      else
        newBestieAcl = new Parse.ACL()
        newBestieAcl.setRoleReadAccess "#{user.id}_Friends", true
        newBestieAcl.setReadAccess user.id, true
        newBestie = new Parse.Object 'Bestie'
        newBestie.set 'score', points
        newBestie.set 'cards', 1
        newBestie.set 'level', 1
        newBestie.set 'friend', peggee
        newBestie.set 'user', user
        newBestie.set 'ACL', newBestieAcl
        newBestie.save({ useMasterKey: true })
          .then => console.log "updateBestieScore: success -- #{JSON.stringify bestie}"
          .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify bestie}"


updateCardHasPreffed = (user, card) ->
  token = user.getSessionToken()
  # UPDATE card row with userId in hasPreffed array
  cardQuery = new Parse.Query 'Card'
  cardQuery.equalTo 'objectId', card.id
  cardQuery.first({ sessionToken: token })
    .then (card) ->
    # TODO: if card is user created, uncomment the ACL code below. Chaincasting!
#      cardAcl = card.get 'ACL'
#      if cardAcl isnt undefined
#        console.log "ACL added to card #{card.id}: #{user.id}_Friends"
#        cardAcl.setRoleReadAccess "#{user.id}_Friends", true
#        card.setACL cardAcl
      card.addUnique 'hasPreffed', user.id
      card.save({ useMasterKey: true })
      console.log "hasPreffed saved: #{card.id}"
    .fail ->
      console.log 'hasPreffed failed'

# must not be called with useMasterKey enabled
getCardPrefsByFriends = (user, card) ->
  token = user.getSessionToken()
  prefQuery = new Parse.Query 'Pref'
  prefQuery.equalTo 'card', card
  prefQuery.notEqualTo 'user', user
  prefQuery.limit 1000
  prefQuery.find({ sessionToken: token })
