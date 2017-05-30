class Utils

  makeObject: (type, columns) =>
    obj = new Parse.Object type
    for own name, value of columns
      obj.set name, value
    obj

module.exports = new Utils
