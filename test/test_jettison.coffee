expect = require('chai').expect
jettison = require('../jettison')

StreamView = jettison._StreamView


class Approx

  constructor: (@value, @epsilon) ->


describe 'jettison', ->
  [
    {
      type: 'boolean'
      byteLength: 1
      values: [false, true]
      packed: [[0], [1]]
      unpacked: [false, true]
    }
    {
      type: 'int8'
      byteLength: 1
      values: [0, 1, -1, -128, 127, -129, 128]
      packed: [[0], [1], [255], [128], [127], [128], [127]]
      unpacked: [0, 1, -1, -128, 127, -128, 127]
    }
    {
      type: 'int16'
      byteLength: 2
      values: [0, 1, -1, -32768, 32767, -32769, 32768]
      packed: [[0, 0], [0, 1], [255, 255], [128, 0], [127, 255], [128, 0], [127, 255]]
      unpacked: [0, 1, -1, -32768, 32767, -32768, 32767]
    }
    {
      type: 'int32'
      byteLength: 4
      values: [0, 1, -1, -2147483648, 2147483647, -2147483649, 2147483648]
      packed: [[0, 0, 0, 0], [0, 0, 0, 1], [255, 255, 255, 255],
               [128, 0, 0, 0], [127, 255, 255, 255],
               [128, 0, 0, 0], [127, 255, 255, 255]]
      unpacked: [0, 1, -1, -2147483648, 2147483647, -2147483648, 2147483647]
    }
    {
      type: 'uint8'
      byteLength: 1
      values: [0, 1, 255, -1, 256]
      packed: [[0], [1], [255], [0], [255]]
      unpacked: [0, 1, 255, 0, 255]
    }
    {
      type: 'uint16'
      byteLength: 2
      values: [0, 1, 65535, -1, 65536]
      packed: [[0, 0], [0, 1], [255, 255], [0, 0], [255, 255]]
      unpacked: [0, 1, 65535, 0, 65535]
    }
    {
      type: 'uint32'
      byteLength: 4
      values: [0, 1, 4294967295, -1, 4294967296]
      packed: [
        [0, 0, 0, 0],
        [0, 0, 0, 1],
        [255, 255, 255, 255],
        [0, 0, 0, 0],
        [255, 255, 255, 255]
      ]
      unpacked: [0, 1, 4294967295, 0, 4294967295]
    }
    {
      type: 'float32'
      byteLength: 4
      values: [
        NaN,
        Infinity,
        -Infinity,
        0,
        -0,
        1,
        -1,
        0.5,   # This tests negative exponents.
        10.5,  # This tests normalized values with a decimal component.
        1e-40, # This tests denormalized values.
        1e39,  # This tests overflow.
        ],
      packed: [
        [127, 128, 0, 1],
        [127, 128, 0, 0],
        [255, 128, 0, 0],
        [0, 0, 0, 0],
        [128, 0, 0, 0],
        [63, 128, 0, 0],
        [191, 128, 0, 0],
        [63, 0, 0, 0],
        [65, 40, 0, 0],
        [0, 1, 22, 194],
        [127, 128, 0, 0],
      ]
      unpacked: [NaN, Infinity, -Infinity, 0, -0, 1, -1, 0.5, 10.5,
                 new Approx(1e-40, 0.001), Infinity]
    }
    {
      type: 'float64'
      byteLength: 8
      values: [
        NaN,
        Infinity,
        -Infinity,
        0,
        -0,
        1,
        -1,
        0.5,     # This tests negative exponents
        10.234,  # This tests normalized values with a decimal component.
        1e-310,  # This tests denormalized values.
      ],
      packed: [
        [127, 240, 0, 0, 0, 0, 0, 1],
        [127, 240, 0, 0, 0, 0, 0, 0],
        [255, 240, 0, 0, 0, 0, 0, 0],
        [0, 0, 0, 0, 0, 0, 0, 0],
        [128, 0, 0, 0, 0, 0, 0, 0],
        [63, 240, 0, 0, 0, 0, 0, 0],
        [191, 240, 0, 0, 0, 0, 0, 0],
        [63, 224, 0, 0, 0, 0, 0, 0],
        [64, 36, 119, 206, 217, 22, 135, 43],
        [0, 0, 18, 104, 139, 112, 230, 43],
        [127, 240, 0, 0, 0, 0, 0, 0],
      ]
      unpacked: [NaN, Infinity, -Infinity, 0, -0, 1, -1, 0.5, 10.234, 1e-310]
    }
  ].forEach (test) ->

    it "should have a #{test.type} codec", ->
      codec = jettison._codecs[test.type]
      expect(codec).to.exist
      expect(codec.byteLength).to.equal(test.byteLength)
      for value, index in test.values
        # test little endian packing
        for littleEndian in [false, true]
          streamView = StreamView.create(codec.byteLength)
          codec.set(streamView, value, littleEndian)
          expect(streamView.byteOffset).to.equal(codec.byteLength)
          packed = streamView.toArray()
          expectedPacked = test.packed[index]
          if littleEndian
            expectedPacked = expectedPacked.slice().reverse()
          expect(packed).to.deep.equal(expectedPacked)

          streamView.byteOffset = 0
          unpacked = codec.get(streamView, littleEndian)
          expectedUnpacked = test.unpacked[index]
          if expectedUnpacked instanceof Approx
            expect(Math.abs(unpacked - expectedUnpacked.value))
              .to.be.lessThan(expectedUnpacked.epsilon)
          else if isNaN(expectedUnpacked)
            expect(isNaN(unpacked)).to.be.true
          else
            expect(unpacked).to.equal(expectedUnpacked)

  it 'should approximately convert float32 values', ->
    codec = jettison._codecs.float32
    streamView = StreamView.create(codec.byteLength)
    codec.set(streamView, 1.00001, false)
    streamView.byteOffset = 0
    unpacked = codec.get(streamView, false)
    expect(Math.abs(unpacked - 1.00001)).to.be.lessThan(1e-6)

  it 'should have a string codec', ->
    codec = jettison._codecs.string
    expect(codec).to.exist
    streamView = StreamView.create(codec.getByteLength('hodør'))
    expect(streamView.arrayBuffer.byteLength).to.equal(10)
    codec.set(streamView, 'hodør', false)
    expect(streamView.byteOffset).to.equal(10)
    expect(streamView.toArray()).to.deep.equal([
      0, 0, 0, 6, 104, 111, 100, 195, 184, 114])
    streamView.byteOffset = 0
    unpacked = codec.get(streamView, false)
    expect(unpacked).to.equal('hodør')

  it 'should convert between byte arrays and strings', ->
    codec = jettison._codecs.float64
    streamView = StreamView.create(codec.byteLength)
    codec.set(streamView, 1.0000001)
    encoded = streamView.toString()
    expect(typeof encoded).to.equal('string')
    decodedStreamView = StreamView.createFromString(encoded)
    expect(decodedStreamView.toArray()).to.deep.equal(streamView.toArray())

  describe 'definitions', ->
    definition = jettison.define [
      {key: 'id', type: 'int32'}
      {key: 'x', type: 'float64'}
      {key: 'y', type: 'float64'}
      {key: 'points', type: 'array', valueType: 'float64'}
      {key: 'health', type: 'int16'}
    ]
    expectedValue =
      id: 1
      x: 0.5
      y: 1.5
      points: [0.1, 0.2, 0.3, 0.4]
      health: 100
    streamView = StreamView.create(definition.getByteLength(expectedValue))
    definition.set(streamView, expectedValue)
    string = definition.stringify(expectedValue)

    before ->
      streamView.byteOffset = 0

    it 'should convert native values to byte arrays', ->
      expect(streamView.toArray()).to.deep.equal([
        0, 0, 0, 1,
        63, 224, 0, 0, 0, 0, 0, 0,
        63, 248, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 4,
        63, 185, 153, 153, 153, 153, 153, 154,
        63, 201, 153, 153, 153, 153, 153, 154,
        63, 211, 51, 51, 51, 51, 51, 51,
        63, 217, 153, 153, 153, 153, 153, 154,
        0, 100,
      ])

    it 'should convert byte arrays back to native values', ->
      value = definition.get(streamView)
      expect(value).to.deep.equal(expectedValue)

    it 'should convert native values to strings', ->
      expect(typeof string).to.equal('string')

    it 'should convert strings back to native values', ->
      value = definition.parse(string)
      expect(value).to.deep.equal(expectedValue)

  describe 'schemas', ->

    schema = jettison.createSchema()
    schema.define 'spawn', [
      {key: 'id', type: 'int32'}
      {key: 'x', type: 'float64'}
      {key: 'y', type: 'float64'}
      {key: 'points', type: 'array', valueType: 'float64'}
    ]
    schema.define 'position', [
      {key: 'id', type: 'int32'}
      {key: 'x', type: 'float64'}
      {key: 'y', type: 'float64'}
    ]

    it 'should convert to and from strings', ->
      expectedValue =
        id: 1
        x: 0.5
        y: 1.5
        points: [-0.1, 0.2, -0.3, 0.4]
      string = schema.stringify('spawn', expectedValue)
      expect(typeof string).to.equal('string')
      value = schema.parse(string)
      expect(value).to.deep.equal(expectedValue)

      expectedValue =
        id: 1
        x: -123.456
        y: 7.89
      string = schema.stringify('position', expectedValue)
      expect(typeof string).to.equal('string')
      value = schema.parse(string)
      expect(value).to.deep.equal(expectedValue)
