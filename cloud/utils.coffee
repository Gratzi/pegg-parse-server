makeObject = (type, columns) =>
  obj = new Parse.Object type
  for own name, value of columns
    obj.set name, value
  obj

failHandler = (error) ->
  console.error "ERROR: #{JSON.stringify error}"

module.exports = {makeObject, failHandler}
