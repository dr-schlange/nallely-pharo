Class {
	#name : 'NallelyConnector',
	#superclass : 'Object',
	#instVars : [
		'host',
		'port',
		'neuronName',
		'parameters',
		'websocket',
		'receiveProcess',
		'onReceiveBlock',
		'reconnectEnabled',
		'reconnectDelay',
		'running'
	],
	#category : 'Nallely-connector',
	#package : 'Nallely',
	#tag : 'connector'
}

{ #category : 'initialization' }
NallelyConnector >> addParameter: paramName range: rangeArray [
	"Add a parameter declaration. rangeArray is #(min max) or #(nil nil) for unbounded"
	parameters add: (Dictionary new at: 'name' put: paramName; at: 'range' put: rangeArray; yourself )
]

{ #category : 'initialization' }
NallelyConnector >> buildRegistrationMessage [
	| dict |
	dict := Dictionary new at: 'kind' put: 'external'; at: 'parameters' put: parameters deepCopy asArray; yourself.
	^ STONJSON toString: dict 
]

{ #category : 'initialization' }
NallelyConnector >> connect [
    "Establish WebSocket connection and register the neuron"
    running := true.
    self performConnection
]

{ #category : 'initialization' }
NallelyConnector >> decodeFloat64BigEndian: byteArray [
    "Decode 8 bytes in big-endian order to a Float"
    | word |
    word := 0.
    
    "Reconstruct the 64-bit word from big-endian bytes"
    1 to: 8 do: [ :i |
        word := (word << 8) bitOr: (byteArray at: i)
    ].
    
    "Convert IEEE 754 bits back to Float"
    ^ Float fromIEEE64BitWord: word
]

{ #category : 'initialization' }
NallelyConnector >> decodeFrame: byteArray [
    "Decode a binary frame into (parameterName, value) pair.
    Returns an Association: parameterName -> value"
    | nameLength nameBytes paramName valueBytes floatValue stream |
    
    stream := ReadStream on: byteArray.
    
    "Read name length (1 byte)"
    nameLength := stream next.
    
    "Read name bytes"
    nameBytes := stream next: nameLength.
    paramName := nameBytes utf8Decoded.
    
    "Read float64 bytes (8 bytes)"
    valueBytes := stream next: 8.
    floatValue := self decodeFloat64BigEndian: valueBytes.
    
    ^ paramName -> floatValue
]

{ #category : 'initialization' }
NallelyConnector >> disconnect [
    "Close the connection and stop reconnection attempts"
    running := false.
    receiveProcess ifNotNil: [ receiveProcess terminate ].
    websocket ifNotNil: [ 
        [ websocket close ] on: Error do: [ :ex | "ignore close errors" ]
    ].
    Transcript show: 'Disconnected from Nallely'; cr
]

{ #category : 'initialization' }
NallelyConnector >> encodeFloat64BigEndian: aFloat [
	| bytes word |
	bytes := ByteArray new: 8.
	word := aFloat asIEEE64BitWord.
	1 to: 8 do: [ :i |
		bytes at: i put: ((word >> (64 - (i * 8))) bitAnd: 16rFF)	
	].
	^ bytes
]

{ #category : 'initialization' }
NallelyConnector >> encodeFrame: parameterName value: floatValue [
	"Encode a binary frame according to the Nallely protocol:
    [1 byte: name_length][N bytes: name_utf8][8 bytes: float64_big_endian]"
	| nameBytes nameLength stream |
	nameBytes := parameterName utf8Encoded.
	nameLength  := nameBytes size.
	
	nameLength > 255 ifTrue: [ self error: 'Parameter name too long: ', nameLength asString ].
	stream := WriteStream on: ByteArray new.
	stream nextPut: nameLength.
	stream nextPutAll: nameBytes.
	stream nextPutAll: (self encodeFloat64BigEndian: floatValue).
	
	^ stream contents
]

{ #category : 'initialization' }
NallelyConnector >> handleBinaryMessage: byteArray [
    "Process a binary frame message"
    | association paramName value |
    association := self decodeFrame: byteArray.
    paramName := association key.
    value := association value.
    
    onReceiveBlock ifNotNil: [ 
        onReceiveBlock value: paramName value: value
    ]
]

{ #category : 'initialization' }
NallelyConnector >> handleMessage: message [
    "Process a received WebSocket message"
    message isText ifFalse: [ 
        ^ self handleBinaryMessage: message
    ].
    
    message isText ifTrue: [ 
        ^ self handleTextMessage: message
    ]
]

{ #category : 'initialization' }
NallelyConnector >> handleTextMessage: jsonString [
    | dict paramName value |
    dict := STONJSON fromString: jsonString.
    
    paramName := dict at: 'on' ifAbsent: [ ^ self ].
    value := dict at: 'value' ifAbsent: [ ^ self ].
    
    onReceiveBlock ifNotNil: [ 
        onReceiveBlock value: paramName value: value
    ]
]

{ #category : 'initialization' }
NallelyConnector >> host: aString [
	host := aString
]

{ #category : 'initialization' }
NallelyConnector >> initialize [
	super initialize.
	host := 'localhost'.
	port := 6789.
	neuronName := 'pharo_neuron'.
	parameters := OrderedCollection new.
	reconnectEnabled := true.
	reconnectDelay := 1 second.
	running := false.
]

{ #category : 'initialization' }
NallelyConnector >> neuronName: aString [
	neuronName := aString
	
]

{ #category : 'initialization' }
NallelyConnector >> onReceive: aBlock [
	onReceiveBlock := aBlock
]

{ #category : 'initialization' }
NallelyConnector >> parameters [
	^ parameters
]

{ #category : 'initialization' }
NallelyConnector >> performConnection [
    "Internal method to establish connection"
    [ 
        | client |
        Transcript show: 'Connecting to ', self url; cr.
        
        client := ZnWebSocket to: self url.
        websocket := client.
        
        "Send registration message"
        websocket sendMessage: self buildRegistrationMessage.
        Transcript show: 'Neuron registered: ', neuronName; cr.
        
        "Start receive loop in background"
        self startReceiveLoop.
        
    ] on: Error do: [ :ex |
        Transcript show: 'Connection failed: ', ex messageText; cr.
        self scheduleReconnect
    ]
]

{ #category : 'initialization' }
NallelyConnector >> port: anInteger [
	port := anInteger 
]

{ #category : 'initialization' }
NallelyConnector >> receiveLoop [
    "Main receive loop - processes incoming messages"
    [ running ] whileTrue: [
        [ 
            | message |
            message := websocket readMessage.				
            message ifNotNil: [ self handleMessage: message ]
        ] on: Error do: [ :ex |
            Transcript show: 'Receive error: ', ex messageText; cr.
            running ifFalse: [ ^ self ].
            "Error in receive - will trigger reconnect via ensure"
            ^ self
        ]
    ]
]

{ #category : 'initialization' }
NallelyConnector >> reconnectDelay: aDuration [
	reconnectDelay := aDuration 
]

{ #category : 'initialization' }
NallelyConnector >> reconnectEnabled: aBoolean [
	reconnectEnabled := aBoolean 
]

{ #category : 'initialization' }
NallelyConnector >> scheduleReconnect [
    "Schedule a reconnection attempt if reconnection is enabled"
    reconnectEnabled ifFalse: [ ^ self ].
    running ifFalse: [ ^ self ].
    
    Transcript show: 'Reconnecting in ', reconnectDelay asSeconds asString, ' seconds...'; cr.
    
    [ 
        reconnectDelay wait.
        running ifTrue: [ self performConnection ]
    ] fork
]

{ #category : 'initialization' }
NallelyConnector >> send: parameterName value: floatValue [
    "Send a value for the given parameter"
    | frame |
    websocket ifNil: [ 
        self error: 'Not connected. Call connect first.'
    ].
    
    frame := self encodeFrame: parameterName value: floatValue.
    websocket sendMessage: frame.
]

{ #category : 'initialization' }
NallelyConnector >> startReceiveLoop [
    "Start a process to receive incoming messages"
    receiveProcess := [ 
        [ self receiveLoop ] ensure: [ 
            Transcript show: 'Receive loop ended'; cr.
            self scheduleReconnect
        ]
    ] forkNamed: 'Nallely Receiver: ', neuronName

]

{ #category : 'initialization' }
NallelyConnector >> url [
	^ 'ws://', host, ':', port asString, '/', neuronName, '/autoconfig'
]
