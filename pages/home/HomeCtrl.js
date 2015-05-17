/**
*/

'use strict';

angular.module('myApp').controller('HomeCtrl', ['$scope', 'spinclient', function($scope, spinclient) {

  var wsio = io('ws://evothings.com:3003');
  spinclient.setWebSocketInstance(wsio);
  /*
  var d = ngSpinClient.listTargets().then(function(targets) {
    console.log ('---list of targets');
    console.dir (targets);

  });
  */

}]);