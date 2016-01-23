SuperModel      = require('spincycle').SuperModel
defer           = require('node-promise').defer
uuid            = require('node-uuid')

class SamplePlayer extends SuperModel

  @type       = 'SamplePlayer'

  @model =
    [
      {name: 'name', public: true, value: 'name', default:  'player'}
      {name: 'something', public: true, value: 'something', default:  {foo:'bar', baz:{x:17, broxo: "yhao"}}}
    ]

  constructor: (@record={}) ->
    return super

module.exports = SamplePlayer