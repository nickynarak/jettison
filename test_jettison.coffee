expect = require('chai').expect
jettison = require('./jettison')

tests = [
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
]

for test in tests
  packer = jettison.packers[test.type]
  for value, index in test.values
    console.log "testing #{test.type} value #{value}"
    expect(packer.length).to.equal(test.length)

    packed = packer.pack(value)
    expect(packed.length).to.equal(test.length)
    expect(packed).to.deep.equal(test.packed[index])
    unpacked = packer.unpack(packed, 0, false)
    if isNaN(value)
      expect(isNaN(unpacked)).to.be.true
    else
      expect(unpacked).to.equal(test.unpacked[index])

    littlePacked = packer.pack(value, true)
    expect(littlePacked.length).to.equal(test.length)
    expect(littlePacked).to.deep.equal(test.packed[index].reverse())
    unpacked = packer.unpack(littlePacked, 0, true)
    if isNaN(value)
      expect(isNaN(unpacked)).to.be.true
    else
      expect(unpacked).to.equal(test.unpacked[index])

console.log 'testing float32 approximate conversion'
unpacked = jettison.packers.float32.unpack(jettison.packers.float32.pack(1.00001))
expect(Math.abs(1.00001 - unpacked)).to.be.lessThan(1e-7)

console.log 'testing encoding and decoding'
packed = jettison.packers.float64.pack(1.0000001)
encoded = jettison.byteArrayToString(packed)
decoded = jettison.stringToByteArray(encoded)
expect(decoded).to.deep.equal(packed)

console.log 'testing packets'
message = jettison.define [
  {key: 'id', type: 'int32'}
  {key: 'x', type: 'float64'}
  {key: 'y', type: 'float64'}
]
bytes = message.toByteArray([1, 0.5, 1.5])
expect(bytes).to.deep.equal([
  0, 0, 0, 1, 63, 224, 0, 0, 0, 0, 0, 0, 63, 248, 0, 0, 0, 0, 0, 0])
values = message.fromByteArray(bytes)
expect(values).to.deep.equal([1, 0.5, 1.5])

