sendinblue = require 'sendinblue-api'

SENDINBLUE_KEY = process.env.SENDINBLUE_KEY or throw new Error "cannot have an empty SENDINBLUE_KEY"
SENDINBLUE_LIST_ID = process.env.SENDINBLUE_LIST_ID or throw new Error "cannot have an empty SENDINBLUE_LIST_ID"
client = new sendinblue { "apiKey": SENDINBLUE_KEY, "timeout": 5000 }

SendInBlue =

  delete: (args) =>
    if !args or !args.email
      console.log 'Must supply email address of user to delete'
      return
    promise = new Parse.Promise()

    client.delete_user args, (err, result) ->
      if err?
        console.error err
        promise.reject err
      else
        console.log result
        promise.resolve result
    promise

  createOrUpdate: (args) =>
    if !args or !args.email or !args.firstName or !args.lastName
      console.log 'Must supply email address, firstname and lastname to SendInBlue createUpdate'
      return

    promise = new Parse.Promise()
    data =
      'email': args.email
      'attributes':
        'FIRSTNAME': args.firstName
        'NAME': args.firstName + ' ' + args.lastName
      'listid': [ SENDINBLUE_LIST_ID ]
    client.create_update_user data, (err, result) ->
      if err?
        console.error err
        promise.reject err
      else
        console.log result
        promise.resolve result
    promise

module.exports = SendInBlue
