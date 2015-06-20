expect = require('chai').expect
jettison = require('../jettison')

describe 'jettison', ->
  [
    {
      type: 'boolean'
      length: 1
      values: [false, true]
      packed: [[0], [1]]
      unpacked: [false, true]
    }
    {
      type: 'int8'
      length: 1
      values: [0, 1, -1, -128, 127, -129, 128]
      packed: [[0], [1], [255], [128], [127], [128], [127]]
      unpacked: [0, 1, -1, -128, 127, -128, 127]
    }
    {
      type: 'int16'
      length: 2
      values: [0, 1, -1, -32768, 32767, -32769, 32768]
      packed: [[0, 0], [0, 1], [255, 255], [128, 0], [127, 255], [128, 0], [127, 255]]
      unpacked: [0, 1, -1, -32768, 32767, -32768, 32767]
    }
    {
      type: 'int32'
      length: 4
      values: [0, 1, -1, -2147483648, 2147483647, -2147483649, 2147483648]
      packed: [[0, 0, 0, 0], [0, 0, 0, 1], [255, 255, 255, 255],
               [128, 0, 0, 0], [127, 255, 255, 255],
               [128, 0, 0, 0], [127, 255, 255, 255]]
      unpacked: [0, 1, -1, -2147483648, 2147483647, -2147483648, 2147483647]
    }
    {
      type: 'uint8'
      length: 1
      values: [0, 1, 255, -1, 256]
      packed: [[0], [1], [255], [0], [255]]
      unpacked: [0, 1, 255, 0, 255]
    }
    {
      type: 'uint16'
      length: 2
      values: [0, 1, 65535, -1, 65536]
      packed: [[0, 0], [0, 1], [255, 255], [0, 0], [255, 255]]
      unpacked: [0, 1, 65535, 0, 65535]
    }
    {
      type: 'uint32'
      length: 4
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
      length: 4
      values: [0, 1, -1, 2, -2, 0.5, -0.5, Infinity, -Infinity, NaN]
      packed: [
        [0, 0, 0, 0],
        [63, 128, 0, 0],
        [191, 128, 0, 0],
        [64, 0, 0, 0],
        [192, 0, 0, 0],
        [63, 0, 0, 0],
        [191, 0, 0, 0],
        [127, 128, 0, 0],
        [255, 128, 0, 0],
        [127, 128, 0, 1],
      ]
      unpacked: [0, 1, -1, 2, -2, 0.5, -0.5, Infinity, -Infinity, NaN]
    }
    {
      type: 'float64'
      length: 8
      values: [0, 1, -1, 2, -2, 0.1, -0.1, 1.0000001, Infinity, -Infinity, NaN]
      packed: [
        [0, 0, 0, 0, 0, 0, 0, 0],
        [63, 240, 0, 0, 0, 0, 0, 0],
        [191, 240, 0, 0, 0, 0, 0, 0],
        [64, 0, 0, 0, 0, 0, 0, 0],
        [192, 0, 0, 0, 0, 0, 0, 0],
        [63, 185, 153, 153, 153, 153, 153, 154],
        [191, 185, 153, 153, 153, 153, 153, 154],
        [63, 240, 0, 0, 26, 215, 242, 155],
        [127, 240, 0, 0, 0, 0, 0, 0],
        [255, 240, 0, 0, 0, 0, 0, 0],
        [127, 240, 0, 0, 0, 0, 0, 1],
      ]
      unpacked: [0, 1, -1, 2, -2, 0.1, -0.1, 1.0000001, Infinity, -Infinity, NaN]
    }
  ].forEach (test) ->

    it "should have a #{test.type} packer", ->
      packer = jettison._packers[test.type]
      expect(packer).to.exist
      expect(packer.length).to.equal(test.length)
      for value, index in test.values
        # test little endian packing
        packed = packer.pack(value)
        expect(packed.length).to.equal(test.length)
        expect(packed).to.deep.equal(test.packed[index])
        unpacked = packer.unpack(packed, 0, false)
        if isNaN(value)
          expect(isNaN(unpacked)).to.be.true
        else
          expect(unpacked).to.equal(test.unpacked[index])
        # test big endian packing
        littlePacked = packer.pack(value, true)
        expect(littlePacked.length).to.equal(test.length)
        expect(littlePacked).to.deep.equal(test.packed[index].reverse())
        unpacked = packer.unpack(littlePacked, 0, true)
        if isNaN(value)
          expect(isNaN(unpacked)).to.be.true
        else
          expect(unpacked).to.equal(test.unpacked[index])

  it 'should be approximately convert float32 values', ->
    unpacked = jettison._packers.float32.unpack(jettison._packers.float32.pack(1.00001))
    expect(Math.abs(1.00001 - unpacked)).to.be.lessThan(1e-7)

  it 'should convert between byte arrays and strings', ->
    packed = jettison._packers.float64.pack(1.0000001)
    encoded = jettison._byteArrayToString(packed)
    expect(typeof encoded).to.equal('string')
    decoded = jettison._stringToByteArray(encoded)
    expect(decoded).to.deep.equal(packed)

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
    bytes = definition.toByteArray(expectedValue)
    string = definition.stringify(expectedValue)

    it 'should convert native values to byte arrays', ->
      # test packing and unpacking the definition
      expect(bytes).to.deep.equal([
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
      value = definition.fromByteArray(bytes)
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
