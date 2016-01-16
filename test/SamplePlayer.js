// Generated by CoffeeScript 1.9.3
(function() {
  var SamplePlayer, SuperModel, defer, uuid,
    extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  SuperModel = require('spincycle').SuperModel;

  defer = require('node-promise').defer;

  uuid = require('node-uuid');

  SamplePlayer = (function(superClass) {
    extend(SamplePlayer, superClass);

    SamplePlayer.type = 'SamplePlayer';

    SamplePlayer.model = [
      {
        name: 'name',
        "public": true,
        value: 'name',
        "default": 'player'
      }
    ];

    function SamplePlayer(record) {
      this.record = record != null ? record : {};
      return SamplePlayer.__super__.constructor.apply(this, arguments);
    }

    return SamplePlayer;

  })(SuperModel);

  module.exports = SamplePlayer;

}).call(this);

//# sourceMappingURL=SamplePlayer.js.map
