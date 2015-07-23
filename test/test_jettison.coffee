expect = require('chai').expect
jettison = require('../src/jettison')

StreamView = jettison._StreamView

class Approx

  constructor: (@value, @epsilon) ->


describeJettison = ({withPolyfills}={}) ->

  describe "jettison#{if withPolyfills then ' with polyfills' else ''}", ->

    before ->
      if withPolyfills
        jettison._config.ArrayBuffer = jettison._polyfill.ArrayBufferPolyfill
        jettison._config.DataView = jettison._polyfill.DataViewPolyfill
      else
        jettison._config.ArrayBuffer = global.ArrayBuffer
        jettison._config.DataView = global.DataView

    testEndianCodec = (codec, inValue, expectedBytes, expectedOutValue,
                       littleEndian) ->
      streamView = StreamView.create(codec.byteLength)
      codec.set(streamView, inValue, littleEndian)
      expect(streamView.byteOffset).to.equal(codec.byteLength)
      bytes = streamView.toArray()
      if littleEndian
        expectedBytes = expectedBytes.slice().reverse()
      expect(bytes).to.deep.equal(expectedBytes)

      streamView.byteOffset = 0
      outValue = codec.get(streamView, littleEndian)
      if expectedOutValue instanceof Approx
        expect(Math.abs(outValue - expectedOutValue.value))
          .to.be.lessThan(expectedOutValue.epsilon)
      else if isNaN(expectedOutValue)
        expect(isNaN(outValue)).to.be.true
      else
        expect(outValue).to.equal(expectedOutValue)

    testCodec = (codec, inValue, expectedBytes, expectedOutValue) ->
      testEndianCodec(codec, inValue, expectedBytes, expectedOutValue, false)
      testEndianCodec(codec, inValue, expectedBytes, expectedOutValue, true)

    it 'should convert boolean values', ->
      codec = jettison._codecs.boolean
      testCodec(codec, false, [0], false)
      testCodec(codec, true, [1], true)

    it 'should convert int8 values', ->
      codec = jettison._codecs.int8
      testCodec(codec, 0, [0], 0)
      testCodec(codec, 1, [1], 1)
      testCodec(codec, -1, [255], -1)
      testCodec(codec, -128, [128], -128)
      testCodec(codec, 127, [127], 127)
      testCodec(codec, -129, [128], -128)
      testCodec(codec, 128, [127], 127)

    it 'should convert int16 values', ->
      codec = jettison._codecs.int16
      testCodec(codec, 0, [0, 0], 0)
      testCodec(codec, 1, [0, 1], 1)
      testCodec(codec, -1, [255, 255], -1)
      testCodec(codec, -32768, [128, 0], -32768)
      testCodec(codec, 32767, [127, 255], 32767)
      testCodec(codec, -32769, [128, 0], -32768)
      testCodec(codec, 32768, [127, 255], 32767)

    it 'should convert int32 values', ->
      codec = jettison._codecs.int32
      testCodec(codec, 0, [0, 0, 0, 0], 0)
      testCodec(codec, 1, [0, 0, 0, 1], 1)
      testCodec(codec, -1, [255, 255, 255, 255], -1)
      testCodec(codec, -2147483648, [128, 0, 0, 0], -2147483648)
      testCodec(codec, 2147483647, [127, 255, 255, 255], 2147483647)
      testCodec(codec, -2147483649, [128, 0, 0, 0], -2147483648)
      testCodec(codec, 2147483648, [127, 255, 255, 255], 2147483647)

    it 'should convert uint8 values', ->
      codec = jettison._codecs.uint8
      testCodec(codec, 0, [0], 0)
      testCodec(codec, 1, [1], 1)
      testCodec(codec, 255, [255], 255)
      testCodec(codec, -1, [0], 0)
      testCodec(codec, 256, [255], 255)

    it 'should convert uint16 values', ->
      codec = jettison._codecs.uint16
      testCodec(codec, 0, [0, 0], 0)
      testCodec(codec, 1, [0, 1], 1)
      testCodec(codec, 65535, [255, 255], 65535)
      testCodec(codec, -1, [0, 0], 0)
      testCodec(codec, 65536, [255, 255], 65535)

    it 'should convert uint32 values', ->
      codec = jettison._codecs.uint32
      testCodec(codec, 0, [0, 0, 0, 0], 0)
      testCodec(codec, 1, [0, 0, 0, 1], 1)
      testCodec(codec, 4294967295, [255, 255, 255, 255], 4294967295)
      testCodec(codec, -1, [0, 0, 0, 0], 0)
      testCodec(codec, 4294967296, [255, 255, 255, 255], 4294967295)

    it 'should convert float32 values', ->
      codec = jettison._codecs.float32
      testCodec(codec, NaN, [127, 192, 0, 0], NaN)
      testCodec(codec, Infinity, [127, 128, 0, 0], Infinity)
      testCodec(codec, -Infinity, [255, 128, 0, 0], -Infinity)
      testCodec(codec, 0, [0, 0, 0, 0], 0)
      testCodec(codec, -0, [128, 0, 0, 0], 0)
      testCodec(codec, 1, [63, 128, 0, 0], 1)
      testCodec(codec, -1, [191, 128, 0, 0], -1)
      # Negative exponent
      testCodec(codec, 0.5, [63, 0, 0, 0], 0.5)
      # Normalized value with a decimal component
      testCodec(codec, 10.5, [65, 40, 0, 0], 10.5)
      # Denormalized value
      testCodec(codec, 1e-40, [0, 1, 22, 194], new Approx(1e-40, 0.001))
      # Overflow should become infinity
      testCodec(codec, 1e+39, [127, 128, 0, 0], Infinity)
      # Rounding
      testCodec(codec, 1.00001, [63, 128, 0, 84], new Approx(1.00001, 1e-7))

    it 'should convert float64 values', ->
      codec = jettison._codecs.float64
      testCodec(codec, NaN, [127, 248, 0, 0, 0, 0, 0, 0], NaN)
      testCodec(codec, Infinity, [127, 240, 0, 0, 0, 0, 0, 0], Infinity)
      testCodec(codec, -Infinity, [255, 240, 0, 0, 0, 0, 0, 0], -Infinity)
      testCodec(codec, 0, [0, 0, 0, 0, 0, 0, 0, 0], 0)
      testCodec(codec, -0, [128, 0, 0, 0, 0, 0, 0, 0], 0)
      testCodec(codec, 1, [63, 240, 0, 0, 0, 0, 0, 0], 1)
      testCodec(codec, -1, [191, 240, 0, 0, 0, 0, 0, 0], -1)
      # Negative exponent
      testCodec(codec, 0.5, [63, 224, 0, 0, 0, 0, 0, 0], 0.5)
      # Normalized value with a decimal component
      testCodec(codec, 10.234, [64, 36, 119, 206, 217, 22, 135, 43], 10.234)
      # Denormalized value
      testCodec(codec, 1e-310, [0, 0, 18, 104, 139, 112, 230, 43], 1e-310)

    it 'should convert string values', ->
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

if global.ArrayBuffer? and global.DataView?
  describeJettison()
describeJettison(withPolyfills: true)
