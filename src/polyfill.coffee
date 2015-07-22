# This file contains things used to polyfill ArrayBuffer and DataView on
# platforms that don't support them natively. Note that the polyfills here
# aren't 100% compatible with the real things -- just good enough for the
# needs of Jettison.


log2 = Math.log2 or (value) -> Math.log(value) / Math.LN2


class FloatPolyfill

  # Oh boy, you're going to try to read this code, eh?
  #
  # It's a bit difficult to follow, so here's a quick summary of the way
  # IEEE-754 floating point encoding works. The floating point value is
  # deconstructed into three separate values: a signed bit, an exponent, and a
  # significand. These three values can be combined to recreate the original
  # float with the formula:
  #
  #     sign * Math.pow(2, exponent) * significand
  #
  # The sign value always gets 1 bit, and the number of bits for the other two
  # depends on the total storage allowed (4 bytes for float32, 8 bytes for
  # float64). For a float32, the significand gets 23 bits and the exponent gets
  # 8. For example, for a big endian float32 value, the components are laid out
  # most significant to least significant like so:
  #
  # - sign (bit 0)
  # - exponent (bits 1..9)
  # - significand (bits 10..32)
  #
  # There are some special cases for representing special values:
  #
  # - NaN has all the exponent and significand bits set.
  # - Infinity has all the exponent bits set, all the significand bits unset,
  #   and the sign bit unset. -Infinity is the same, but the sign bit is set.
  # - An exponent with all the bits unset represents a denormalized value (or
  #   zero, if all the significand bits are also unset).
  # - Anything else is a normalized value.
  #
  # As for the difference between normalized and denormalized values... I'm
  # getting out of my knowledge area here, but normalized values are ones that
  # are representable using both an exponent and a significand component.
  # Denormalized values represent the range between the smallest possible
  # normalized value and zero.
  #
  # So, that is to say, if you had a normalized value with an exponent with the
  # least significant bit set, and a significand with all bits unset, your
  # value is something like 1.17549435E-38. For a denormalized value where all
  # bits of the exponent are unset and all bits of the significand are set is
  # something like 1.1754942E-38 -- just below the smallest normalized value.
  #
  # You'll find a far better explanation here:
  # http://stackoverflow.com/a/15142269/648615
  #
  # This floating point calculator is fun for playing around with bit values:
  # http://www.h-schmidt.net/FloatConverter/IEEE754.html
  #
  #
  # Encoding
  # --------
  #
  # Encoding gets a little mathy. I'll try to walk through it. We're trying to
  # calculate exponent and significand such that:
  #
  #     2^x * s = v
  #
  # Where `v` is the absolute value of the native float that we are encoding,
  # `x` is the exponent, and `s` is the significand.
  #
  # Let's look at exponent first. Remember that a logarithm base 2 of a value
  # gives you the exponent you need to raise 2 to get the value. That is to
  # say, if you ignore the significand, you can solve for `x` like so:
  #
  #     2^x == v
  #     x == log10(v) / log10(2)
  #
  # However, for IEEE 754 encoding, we need the exponent to be a whole number,
  # and most numbers aren't an even power of 2. For example:
  #
  #     > Math.log2(0.1)
  #     -3.321928094887362
  #     > Math.log2(2)
  #     1
  #     > Math.log2(3)
  #     1.584962500721156
  #     > Math.log2(4)
  #     2
  #
  # We end up getting non-integer values. This is where the significand comes
  # in. We need to ensure that the exponent is an integer, and then make the
  # significand `s` where `1 <= s < 2`, and multiplying `pow(2, x)` by `s`
  # gives us `v`. IEEE 754 also makes the whole part (the 1 in 1.23) implicit.
  # So our updated formula for `x` must be:
  #
  #     x = floor(log10(v) / log10(2))
  #
  # And our formula for `s` is:
  #
  #     2^x * (1 + s) = v
  #     s + 1 = v / 2^x
  #     s + 1 = v * (1 / 2^x)
  #     s + 1 = v * 2^-x
  #     s = (v * 2^-x) - 1
  #
  #
  # Exponent Bias
  # -------------
  #
  # The exponent's range is limited by the number of bits available to it. In
  # the case of a float64, the exponent has 11 bits, which gives us an unsigned
  # maximum of:
  #
  #     > parseInt('11111111111', 2)
  #     2047
  #
  # But the cases where all the bits are on or off for an exponent have special
  # meaning (all bits off means it's zero or a denormalized number, all on
  # means NaN or Infinity). This means that we need to leave the least
  # significant bit unset for the maximum, which means our maximum and minimum
  # unsigned ranges representable in a float64 exponent are:
  #
  #     > parseInt('11111111110', 2)
  #     2046
  #     > parseInt('00000000001', 2)
  #     1
  #
  # But the exponent is signed. The IEEE 754 way to deal with this is to add a
  # bias of half the maximum to the signed exponent to get it into the unsigned
  # range, which means our *actual* signed exponent range for float64 is:
  #
  #     > bias = 2046 / 2
  #     1023
  #     > parseInt('11111111110', 2) - bias
  #     1023
  #     > parseInt('00000000001', 2) - bias
  #     -1022
  #
  # Hope this helps make the code a little easier to grok.

  constructor: ({@byteLength, @numSignificandBits, @roundTo}) ->
    @numExponentBits = @byteLength * 8 - @numSignificandBits - 1
    @exponentMax = (1 << @numExponentBits) - 1
    @exponentBias = @exponentMax >> 1
    @roundTo ?= 0

  get: (bytes, byteOffset, littleEndian) ->
    if littleEndian
      # For little endian, start at the end and read backwards, because we're
      # reading the most significant bytes first.
      i = @byteLength - 1
      increment = -1
    else
      i = 0
      increment = 1

    # For the first byte, the high bit is the signed bit.
    # The rest is part of the exponent.
    signedAndExponent = bytes[byteOffset + i]
    signed = (signedAndExponent >> 7)
    exponent = signedAndExponent & 127
    i += increment

    # Keep reading bytes until we've read the whole exponent.
    remainingExponentBits = @numExponentBits - 7
    while remainingExponentBits > 0
        exponent = exponent * 256 + bytes[byteOffset + i]
        remainingExponentBits -= 8
        i += increment

    # Part of our last byte will be shared between the significand and exponent
    # values, so we need to chop it up like we did with the signed bit. If
    # numBits is -7, then we had 7 bits of the significand in the last byte.
    significand = exponent & ((1 << -remainingExponentBits) - 1)
    exponent >>= -remainingExponentBits
    remainingSignificandBits = @numSignificandBits + remainingExponentBits

    # Keep reading until we've read the whole significand.
    while remainingSignificandBits > 0
      significand = significand * 256 + bytes[byteOffset + i]
      remainingSignificandBits -= 8
      i += increment

    # Handle special cases indicated by the value of exponent.
    switch exponent
      when 0
        # Zero, or denormalized number.
        exponent = 1 - @exponentBias
      when @exponentMax
        # NaN, or +/-Infinity.
        return if significand
          NaN
        else if signed
          -Infinity
        else
          Infinity
      else
        # Normalized number.
        significand += Math.pow(2, @numSignificandBits)
        exponent -= @exponentBias
    return ((if signed then -1 else 1) * significand *
            Math.pow(2, exponent - @numSignificandBits))

  set: (bytes, byteOffset, value, littleEndian) ->
    if isNaN(value)
      signed = 0
      biasedExponent = @exponentMax
      significand = Math.pow(2, @numSignificandBits - 1)
    else if value == Infinity
      signed = 0
      biasedExponent = @exponentMax
      significand = 0
    else if value == -Infinity
      signed = 1
      biasedExponent = @exponentMax
      significand = 0
    else if value == 0
      signed = if 1 / value == -Infinity then 1 else 0
      biasedExponent = 0
      significand = 0
    else
      signed = if value < 0 then 1 else 0
      absValue = Math.abs(value)
      exponent = Math.floor(log2(absValue))
      coefficient = Math.pow(2, -exponent)
      if absValue * coefficient < 1
        # Apparently Math.log() isn't 100% reliable? I haven't een a case yet
        # where it doesn't give us the correct value, but the original jspack
        # code had a comment and this logic, so I'll leave it.
        exponent -= 1
        coefficient *= 2

      # Round by adding 1/2 the significand's least significant digit
      if exponent + @exponentBias >= 1
          # Normalized: numSignificandBits significand digits
          absValue += (@roundTo / coefficient)
      else
          # Denormalized: <= numSignificandBits significand digits
          absValue += (@roundTo * Math.pow(2, 1 - @exponentBias))

      if absValue * coefficient >= 2
        # Rounding can mean we need to increment the exponent
        exponent += 1
        coefficient /= 2

      biasedExponent = exponent + @exponentBias
      if biasedExponent >= @exponentMax
        # This exponent is too large to be represented by the number of bits
        # that this type of float allows to the exponent. This means the value
        # has overflowed, and will be treated as Infinity instead.
        significand = 0
        biasedExponent = @exponentMax
      else if biasedExponent < 1
        # Denormalized.
        significand = (absValue * Math.pow(2, @exponentBias - 1) *
                       Math.pow(2, @numSignificandBits))
        biasedExponent = 0
      else
        # Normalized, calculate the significand the regular way. Note that term
        # order matters to prevent overflows in this calculation.
        significand = ((absValue * coefficient - 1) *
                       Math.pow(2, @numSignificandBits))

    @_floatPartsToByteArray(bytes, byteOffset, signed, biasedExponent,
                            significand, littleEndian)

  # This function does just the byte encoding, after the float has been
  # separated into the component parts required for IEEE-754 encoding.
  _floatPartsToByteArray: (bytes, byteOffset, signed, exponent, significand,
                           littleEndian) ->
    if littleEndian
      i = 0
      increment = 1
    else
      # If big endian, start at the end and write backwards, because we're
      # writing the least significant bytes first.
      i = @byteLength - 1
      increment = -1

    remainingSignificandBits = @numSignificandBits
    while remainingSignificandBits >= 8
      bytes[byteOffset + i] = significand & 0xff
      significand /= 256
      remainingSignificandBits -= 8
      i += increment

    # We're encoding whole bytes, but the different components aren't byte
    # aligned, so part of the significand can bleed into the exponent. This
    # handles encoding those leftover bits into the exponent's bytes.
    exponent = (exponent << remainingSignificandBits) | significand
    remainingExponentBits = @numExponentBits + remainingSignificandBits
    while remainingExponentBits > 0
      bytes[byteOffset + i] = exponent & 0xff
      exponent /= 256
      remainingExponentBits -= 8
      i += increment

    bytes[byteOffset + i - increment] |= signed * 128

    @byteLength


class IntegerPolyfill

  constructor: ({@byteLength, @signed}) ->
    @bitLength = @byteLength * 8
    if @signed
      @signBit = Math.pow(2, @bitLength - 1)
      @minValue = -Math.pow(2, @bitLength - 1)
      @maxValue = Math.pow(2, @bitLength - 1) - 1
    else
      @minValue = 0
      @maxValue = Math.pow(2, @bitLength) - 1

  get: (bytes, byteOffset, littleEndian) ->
    if littleEndian
      i = 0
      increment = 1
    else
      i = @byteLength - 1
      increment = -1
    value = 0
    scale = 1
    stop = i + (increment * @byteLength)
    while i != stop
      value += bytes[byteOffset + i] * scale
      i += increment
      scale *= 256
    if @signed and (value & @signBit)
      value -= Math.pow(2, @bitLength)
    value

  set: (bytes, byteOffset, value, littleEndian) ->
    if littleEndian
      i = 0
      increment = 1
    else
      i = @byteLength - 1
      increment = -1
    value = if value < @minValue
      @minValue
    else if value > @maxValue
      @maxValue
    else
      value
    stop = i + (increment * @byteLength)
    while i != stop
      bytes[byteOffset + i] = value & 255
      i += increment
      value >>= 8
    @byteLength


# These are some polyfills for the ArrayBuffer and DataView classes. Note that
# they aren't complete polyfills, just enough for Jettison's needs.

class ArrayBufferPolyfill

  constructor: (length) ->
    @_bytes = new Array(length)
    @byteLength = length


class DataViewPolyfill

  _polyfills:
    float32: new FloatPolyfill
      byteLength: 4
      numSignificandBits: 23
      # This constant is from jspack's code. I don't understand how this
      # ends up being half of float32's least significant digit... isn't that
      # Math.pow(2, -126)? But it works...
      roundTo: Math.pow(2, -24) - Math.pow(2, -77)
    float64: new FloatPolyfill
      byteLength: 8
      numSignificandBits: 52
    int8: new IntegerPolyfill(byteLength: 1, signed: true)
    int16: new IntegerPolyfill(byteLength: 2, signed: true)
    int32: new IntegerPolyfill(byteLength: 4, signed: true)
    uint8: new IntegerPolyfill(byteLength: 1, signed: false)
    uint16: new IntegerPolyfill(byteLength: 2, signed: false)
    uint32: new IntegerPolyfill(byteLength: 4, signed: false)

  constructor: (@buffer, byteOffset, byteLength) ->
    @byteOffset = byteOffset ? 0
    @byteLength = byteLength ? @buffer.byteLength
    if @byteOffset < @buffer.byteOffset
      throw new RangeError('Start offset is outside the bounds of the buffer')
    else if @byteOffset + @byteLength > @buffer.byteOffset + @buffer.byteLength
      throw new RangeError('Invalid data view length')

  _get: (polyfill, byteOffset, littleEndian) ->
    byteOffset += @byteOffset
    @_validateRange(byteOffset, polyfill.byteLength)
    value = polyfill.get(@buffer._bytes, byteOffset, littleEndian)

  _set: (polyfill, byteOffset, value, littleEndian) ->
    byteOffset += @byteOffset
    @_validateRange(byteOffset, polyfill.byteLength)
    polyfill.set(@buffer._bytes, byteOffset, value, littleEndian)

  _validateRange: (byteOffset, byteLength) ->
    if typeof byteOffset != 'number'
      throw new TypeError('Invalid byteOffset argument')
    if byteOffset < @byteOffset
      throw new RangeError('Offset is outside the bounds of the DataView')
    else if byteOffset + byteLength > @byteOffset + @byteLength
      throw new RangeError('Invalid data view length')

  getFloat32: (byteOffset, littleEndian) ->
    @_get(@_polyfills.float32, byteOffset, littleEndian)

  getFloat64: (byteOffset, littleEndian) ->
    @_get(@_polyfills.float64, byteOffset, littleEndian)

  getInt8: (byteOffset, littleEndian) ->
    @_get(@_polyfills.int8, byteOffset, littleEndian)

  getInt16: (byteOffset, littleEndian) ->
    @_get(@_polyfills.int16, byteOffset, littleEndian)

  getInt32: (byteOffset, littleEndian) ->
    @_get(@_polyfills.int32, byteOffset, littleEndian)

  getUint8: (byteOffset, littleEndian) ->
    @_get(@_polyfills.uint8, byteOffset, littleEndian)

  getUint16: (byteOffset, littleEndian) ->
    @_get(@_polyfills.uint16, byteOffset, littleEndian)

  getUint32: (byteOffset, littleEndian) ->
    @_get(@_polyfills.uint32, byteOffset, littleEndian)

  setFloat32: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.float32, byteOffset, value, littleEndian)

  setFloat64: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.float64, byteOffset, value, littleEndian)

  setInt8: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.int8, byteOffset, value, littleEndian)

  setInt16: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.int16, byteOffset, value, littleEndian)

  setInt32: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.int32, byteOffset, value, littleEndian)

  setUint8: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.uint8, byteOffset, value, littleEndian)

  setUint16: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.uint16, byteOffset, value, littleEndian)

  setUint32: (byteOffset, value, littleEndian) ->
    @_set(@_polyfills.uint32, byteOffset, value, littleEndian)


exports.ArrayBufferPolyfill = ArrayBufferPolyfill
exports.DataViewPolyfill = DataViewPolyfill
exports.FloatPolyfill = FloatPolyfill
exports.IntegerPolyfill = IntegerPolyfill
