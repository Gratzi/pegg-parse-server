

MAILCHIMP_API_KEY = 'MY_MAILCHIMP_KEY'
PEGG_LIST_ID = 'PEGG_LIST_ID'
SERVER = 'SERVER'

MailChimp =

  initialize: =>
    Parse.Config.get().then (config) =>
      MAILCHIMP_API_KEY = config.get 'mailChimpAPIKey'
      PEGG_LIST_ID = config.get 'mailChimpListId'
      SERVER = config.get 'mailChimpServer'

  subscribe: (args) =>
    if !args or !args.email or !args.firstName or !args.lastName
      console.log 'Must supply email address, firstname and lastname to Mailchimp signup'
      return

    MailChimp.initialize().then =>
      mailchimpData =
        apikey: MAILCHIMP_API_KEY
        id: PEGG_LIST_ID
        email: email: args.email
        merge_vars:
          FNAME: args.firstName
          LNAME: args.lastName
        double_optin: false # Facebook already verified their email is valid.
      url = "https://#{SERVER}.api.mailchimp.com/2.0/lists/subscribe.json"

      Parse.Cloud.httpRequest
        method: 'POST'
        url: url
        body: JSON.stringify(mailchimpData)
        success: (httpResponse) ->
          console.log httpResponse.text
        error: (httpResponse) ->
          console.error 'Request failed with response code ' + httpResponse.status
          console.error httpResponse.text

  updateEmail: (args) =>
    if !args or !args.oldEmail or !args.newEmail
      console.log 'Must supply old email address, and new email address'
      return

    MailChimp.initialize().then =>
      mailchimpData =
        apikey: MAILCHIMP_API_KEY
        id: PEGG_LIST_ID
        email: email: args.oldEmail
        merge_vars:
          "new-email": args.newEmail
      url = "https://#{SERVER}.api.mailchimp.com/2.0/lists/update-member.json"

      Parse.Cloud.httpRequest
        method: 'POST'
        url: url
        body: JSON.stringify(mailchimpData)

module.exports = MailChimp
