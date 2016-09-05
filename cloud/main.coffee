_ = require 'underscore'
sha1 = require 'sha1'
facebookImporter = require './facebookImporter'
mailChimp = require './mailchimp'
{makeObject, failHandler} = require './utils'
FirebaseTokenGenerator = require 'firebase-token-generator'
#Parse.Config.get()
#  .then (configs) =>

######### CLOUD FUNCTIONS #########

Parse.Cloud.define "importFriends", facebookImporter.start

Parse.Cloud.define "getFirebaseToken", (request, response) ->
  FIREBASE_SECRET = process.env.FIREBASE_SECRET or throw new Error "cannot have an empty FIREBASE_SECRET"
  tokenGenerator = new FirebaseTokenGenerator FIREBASE_SECRET
  token = tokenGenerator.createToken {uid: request.user.id}, {expires: 2272147200}
  response.success token

Parse.Cloud.define "addFriend", (request, response) ->
  userId = request.user.id
  friendId = request.params.friendId

  forwardPromise = new Parse.Promise()
  backwardPromise = new Parse.Promise()

  Parse.Promise.when(
    forwardPromise
    backwardPromise
  ).then =>
    response.success 'New friend added successfully.'
  , (error) =>
    response.error error

  # add user to Friend's role
  friendRoleName = "#{friendId}_Friends"
  query = new Parse.Query Parse.Role
  query.equalTo "name", friendRoleName
  query.first({ useMasterKey: true })
    .then (friendRole) =>
      if friendRole?
        relation = friendRole.getUsers()
        user = request.user
        user.fetch({ useMasterKey: true })
          .then (user) =>
            relation.add user
            friendRole.save(null, { useMasterKey: true })
              .then =>
                forwardPromise.resolve()
              .fail (error) =>
                forwardPromise.reject error
                console.error "52", error
      else
        forwardPromise.reject "friend role missing: #{friendId}_Friends"
    .fail (error) =>
      console.error "56", error
      forwardPromise.reject error

  # add friend to User's role
  userRoleName = "#{userId}_Friends"
  query = new Parse.Query Parse.Role
  query.equalTo "name", userRoleName
  query.first({ useMasterKey: true })
    .then (userRole) =>
      if userRole?
        relation = userRole.getUsers()
        query = new Parse.Query Parse.User
        query.equalTo "objectId", friendId
        query.first({ useMasterKey: true })
          .then (friend) =>
            relation.add friend
            userRole.save(null, { useMasterKey: true })
            .then =>
              backwardPromise.resolve()
            .fail (error) =>
              backwardPromise.reject error
              console.error "75", error
      else
        backwardPromise.reject "user role missing: #{userId}_Friends"
    .fail (error) =>
      console.error "79", error
      backwardPromise.reject error


######### AFTER SAVE, DELETE, ETC #########

Parse.Cloud.afterSave '_User', (request) ->
  user = request.object
  user.fetch({ useMasterKey: true })
    .then (user) =>
      facebookId = user.get 'facebook_id'
      if !user.existed() and !facebookId?
        roleName = "#{user.id}_Friends"
        console.log "creating role", roleName
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
    failCount = request.object.get 'failCount'
    deck = request.object.get 'deck'

    # Correct! Save stats and update Bestie Score
    if guess.id is answer.id
      updatePrefStats user, card, pref, guess, true
      updateBestieScore user, peggee, failCount, deck
    else
      updatePrefStats user, card, pref, guess, false

Parse.Cloud.afterSave 'Pref', (request) ->
  pref = request.object
  user = request.user
  card = request.object.get 'card'
  answer = request.object.get 'answer'
  deck = request.object.get 'deck'
  question = request.object.get 'question'
  updateCardHasPreffed user, card # updates hasPreffed on Card
  if !pref.existed() # if new object
    incrementChoiceCount answer.id, 'prefCount' # what's the most popular preference?

Parse.Cloud.afterSave 'UserPrivates', (request) ->
# can't use afterSave Parse.User because on new user creation two saves happen, the first without any user details
  userPrivates = request.object
  if !userPrivates.existed() # if new object
    email = userPrivates.get 'email'
    firstName = userPrivates.get 'firstName'
    lastName = userPrivates.get 'lastName'
    console.log "subscribing to MailChimp:", JSON.stringify {email, firstName, lastName}
    mailChimp.subscribe {email, firstName, lastName}

######### UPDATES #########

updatePrefStats = (user, card, pref, guess, correctAnswer) ->
  console.error "updatePrefStats:", pref
  token = user.getSessionToken()
  pref.fetch({sessionToken: token})
    .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"
    .then (pref) =>
      console.log "updatePrefStats: fetched pref -- #{JSON.stringify pref}"
      choices = pref.get('choices')
      if choices?
        choices[guess.id].peggCount++
        pref.set 'choices', choices
      else
        # Sometimes choices don't get populated on Pref creation, not sure why
        console.log "ERROR: aaaaarg choices should exist... refetching..."
        getChoices(card)
          .then (choices) =>
            choices[guess.id].peggCount++
            pref.set 'choices', choices
            pref.save(null, { useMasterKey: true })
      if correctAnswer
        # UPDATE Pref row(s) with userId in hasPegged array
        pref.addUnique 'hasPegged', user.id
      pref.save(null, { useMasterKey: true })
        .fail (err) => console.error "updatePrefStats: ERROR -- #{JSON.stringify err}"
        .then => console.log "updatePrefStats: success -- #{JSON.stringify pref}"

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
        bestie.increment 'failCount', failCount
        bestie.increment 'cards'
        bestie.save(null, { useMasterKey: true })
          .then => console.log "updateBestieScore: success -- #{JSON.stringify bestie}"
          .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify bestie}"
      else
        newBestieAcl = new Parse.ACL()
        newBestieAcl.setRoleReadAccess "#{user.id}_Friends", true
        newBestieAcl.setReadAccess user.id, true
        newBestie = new Parse.Object 'Bestie'
        newBestie.set 'failCount', failCount
        newBestie.set 'cards', 1
        newBestie.set 'friend', peggee
        newBestie.set 'user', user
        peggCounts = {}
        if peggCounts[deck]? then peggCounts[deck]++ else peggCounts[deck] = 1
        newBestie.set 'peggCounts', peggCounts
        newBestie.set 'ACL', newBestieAcl
        newBestie.save(null, { useMasterKey: true })
          .then => console.log "updateBestieScore: success -- #{JSON.stringify newBestie}"
          .fail (err) => console.error "updateBestieScore: ERROR -- #{JSON.stringify newBestie}"

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


######### HELPERS #########

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

incrementCardCount = (cardId, fieldName) ->
  cardQuery = new Parse.Query 'Card'
  cardQuery.equalTo 'objectId', cardId
  cardQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, 1
        result.save(null, { useMasterKey: true })

decrementCardCount = (cardId, fieldName) ->
  cardQuery = new Parse.Query 'Card'
  cardQuery.equalTo 'objectId', cardId
  cardQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, -1
        result.save(null, { useMasterKey: true })

incrementChoiceCount = (choiceId, fieldName) ->
  choiceQuery = new Parse.Query 'Choice'
  choiceQuery.equalTo 'objectId', choiceId
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, 1
        result.save(null, { useMasterKey: true })

decrementChoiceCount = (choiceId, fieldName) ->
  choiceQuery = new Parse.Query 'Choice'
  choiceQuery.equalTo 'objectId', choiceId
  choiceQuery.first({ useMasterKey: true })
    .then (result) =>
      if result?
        result.increment fieldName, -1
        result.save(null, { useMasterKey: true })
