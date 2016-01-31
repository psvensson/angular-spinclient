SuperModel      = require('spincycle').SuperModel
defer           = require('node-promise').defer
uuid            = require('node-uuid')

class FooThing extends SuperModel

  @type       = 'FooThing'

  @model =
    [
      {name: 'name', public: true, value: 'name', default:  'foothing'}
      {name: 'foobar', public: true, value: 'foobar', default:  'xyzzy'}
    ]

  constructor: (@record={}) ->
    return super

module.exports = FooThing