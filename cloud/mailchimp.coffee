MAILCHIMP_API_KEY = process.env.MAILCHIMP_API_KEY or throw new Error "cannot have an empty MAILCHIMP_API_KEY"
MAILCHIMP_LIST_ID = process.env.MAILCHIMP_LIST_ID or throw new Error "cannot have an empty MAILCHIMP_LIST_ID"
MAILCHIMP_SERVER = process.env.MAILCHIMP_SERVER or throw new Error "cannot have an empty MAILCHIMP_SERVER"

MailChimp =

  subscribe: (args) =>
    if !args or !args.email or !args.firstName or !args.lastName
      console.log 'Must supply email address, firstname and lastname to Mailchimp signup'
      return

    mailchimpData =
      apikey: MAILCHIMP_API_KEY
      id: MAILCHIMP_LIST_ID
      email: email: args.email
      merge_vars:
        FNAME: args.firstName
        LNAME: args.lastName
      double_optin: false # Facebook already verified their email is valid.
    url = "https://#{MAILCHIMP_SERVER}.api.mailchimp.com/2.0/lists/subscribe.json"

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

    mailchimpData =
      apikey: MAILCHIMP_API_KEY
      id: MAILCHIMP_LIST_ID
      email: email: args.oldEmail
      merge_vars:
        "new-email": args.newEmail
    url = "https://#{MAILCHIMP_SERVER}.api.mailchimp.com/2.0/lists/update-member.json"

    Parse.Cloud.httpRequest
      method: 'POST'
      url: url
      body: JSON.stringify(mailchimpData)

module.exports = MailChimp
