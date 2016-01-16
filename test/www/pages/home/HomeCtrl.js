angular.module('myApp').controller('HomeCtrl', ['$scope', 'spinclient', function($scope, spinclient) {

    var wsio = io();
    $scope.objects = spinclient.objects;

    $scope.allgames = [];
	$scope.allplayers = [];
    $scope.selectedgame = undefined;

    spinclient.setWebSocketInstance(wsio);
    spinclient.emitMessage({target: '_listSampleGames'}).then(function(list)
    {
        console.log('initial list of games got back..');
        console.dir(list);
        list.forEach(function(user)
        {
            spinclient.objects[user.id] = user;
            $scope.allgames.push(user.id);
        });
    });

	spinclient.emitMessage({target: '_listSamplePlayers'}).then(function(plist)
	{
		console.log('initial list of players got back..');
		console.dir(plist);
		plist.forEach(function(user)
		{
			spinclient.objects[user.id] = user;
			console.log('adding  player '+user.id)
			$scope.allplayers.push(user.id);
		});
	});

  $scope.onselect = function(obj)
  {
      console.log('HomeCtrl game selected');
      console.dir(obj);
      $scope.selectedgame = obj;
  };

  $scope.onselectplayer = function(obj)
  {
    console.log('HomeCtrl player selected');
    console.dir(obj);
    $scope.selectedplayer = obj;
  };

}]);