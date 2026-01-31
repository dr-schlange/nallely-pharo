# nallely-pharo
Nallely connector for Pharo, define your neurons (modules) in Pharo and control Nallely session from Pharo


## Installation

```st
Metacello new
    baseline: 'Nallely';
    repository: 'github://dr-schlange/nallely-pharo:main/src';
    load.
```

## Usage

```st
"creates a new module with 2 ports, output and input"
connector := NallelyConnector new
					host: 'localhost';
					port: 6789;
					neuronName: 'pharo';
					addParameter: 'output' range: #(0 127);
					addParameter: 'input' range: #(0 127);
				connect.

"set the behavior when a message is received"
"we receive the name of the parameter involved and the value"
connector onReceive: [ :parameterName :value |
    "this neuron is only sending the value received summed with 2 on the output port"
	connector send: #output value: (value + 2)
].

"usage command by command if needed"
connector connect.
connector send: #output value: 55.0 .
connector disconnect.
```