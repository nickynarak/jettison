# jettison [![Build Status](https://travis-ci.org/noonat/jettison.svg?branch=master)](https://travis-ci.org/noonat/jettison)

jettison helps you encode binary JavaScript data into strings, so you can send
it over things like WebSockets.


## Getting Started

To use jettison, you need to define a shared schema on the client and server.
Within the schema, you define a set of packets, each with a name and a set of
properties for the packet. These schemas need to match between the client and
the server because the packets are identified by integers. If they don't match,
packets sent by one side won't correspond to the correct definition on the
other side.

Here's an example schema with two packets:

```javascript
var schema = jettison.createSchema();

// This packet could be sent when a new object is created.
//
// The first argument is a unique name for the packet. The second argument is
// the type of value the packet is encoding. For the "object" type used here,
// you also need to pass a list of properties the object can contain (and
// their types).
schema.define('spawn', 'object', [
  {key: 'id', type: 'uint32'},
  {key: 'x', type: 'float64'},
  {key: 'y', type: 'float64'},
  {key: 'color', type: 'uint32'},
  {key: 'health', type: 'int32'},
  {key: 'points', type: 'array', valueType: 'float64'}
]);

// You can also create arrays and other types of packets. This defines a
// "messages" packet, which is an array of strings.
schema.define('messages', 'array', 'string');

// You can then use the schema to encode and decode values, like so:

var string = schema.stringify('spawn', {
  id: 1,
  x: 123.456,
  y: 789.012,
  color: 0x00ffff,
  health: 100,
  points: [
    0.1, 0.2,
    0.3, 0.4,
    0.5, 0.6
  ]
});

var parsed = schema.parse(string);
console.log(parsed.key);   // "spawn"
console.log(parsed.data);  // {"id": 1, "x": 123.456, ...}
```

Types that are currently supported are:

| Type    | Description |
| ------- | ----------- |
| array   | A variable length array of another type. When you use this type, you must also specify a `valueType` field, which will specify the type of value in the array. |
| boolean | 1 byte true or false. |
| booleanArray | A variable length array of booleans. This is encoded as a length and a sequence of bit flags for efficiency. |
| float32 | 4 byte floating point number. Note that normal JavaScript numbers will be rounded to fit this size, so decoded values will only approximately equal the originals. |
| float64 | 8 byte floating point number. Normal JavaScript numbers are stored in this format, so these will be transmitted without rounding. |
| int8    | 1 byte signed integer. Range is -128 to 127 (inclusive). |
| int16   | 2 byte signed integer. Range is -32768 to 32767. |
| int32   | 4 byte signed integer. Range is -2147483648 to 2147483647. |
| object  | A simple object. This codec requires a list of properties (and their types) that the object contains. |
| string  | A variable length string. JavaScript's UTF-16 strings are encoded to UTF-8 for transmission. |
| uint8   | 1 byte unsigned integer. Range is 0 to 255. |
| uint16  | 2 byte unsigned integer. Range is 0 to 65535. |
| uint32  | 4 byte unsigned integer. Range is 0 to 4294967295. |
| variableLength | A variable length unsigned integer. This is used internally by Jettison to represent lengths in as few bytes as possible. |

Note that values out of range will be truncated (so a value of 256 encoded as
a uint8 will be truncated to 255, and a value of -1 will be truncated to 0).
