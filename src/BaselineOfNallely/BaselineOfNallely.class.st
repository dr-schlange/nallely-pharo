Class {
	#name : 'BaselineOfNallely',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfNallely',
	#package : 'BaselineOfNallely'
}

{ #category : 'baselines' }
BaselineOfNallely >> baseline: spec [
    <baseline>
    spec for: #common do: [
        spec
            baseline: 'ZincHTTPComponents'
            with: [ spec repository: 'github://svenvc/zinc/repository';
				loads: #('WebSocket')
	 ].

        spec
            package: 'Nallely' 
            with: [ spec requires: #('ZincHTTPComponents') ].
    ].
]
