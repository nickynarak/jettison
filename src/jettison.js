'use strict';

import * as utf8 from 'utf8';
import * as polyfill from './polyfill.js';


export let _config;
const _globals = typeof global != 'undefined' ? global : window;
if (_globals != null && _globals.ArrayBuffer != null &&
    _globals.DataView != null) {
  _config = {
    ArrayBuffer: _globals.ArrayBuffer,
    DataView: _globals.DataView,
  };
} else {
  _config = {
    ArrayBuffer: polyfill.ArrayBufferPolyfill,
    DataView: polyfill.DataViewPolyfill,
  };
}

export let _codecs = {};


/**
* These codecs are used as simple helpers for getting a value from or setting
* a value on a StreamView object. They handle any clamping that needs to be
* done on the value, and also handle advancing the StreamView's byteOffset.
*
* Codec, BooleanCodec, FloatCodec, and IntegerCodec all have fixed sizes. That
* is, their byteLength is consistent regardless of the values being encoded.
*
* ArrayCodec and StringCodec both have dynamic sizes. Their byte length will
* change depending on the values being encoded. For these codecs, you can get
* the byte length by calling `getByteLength()`.
*/
class Codec {
  constructor({byteLength, getter, setter}) {
    this.byteLength = byteLength;
    this.getter = getter;
    this.setter = setter;
    if (this.byteLength <= 0) {
      throw new Error('byteLength must be a positive integer');
    }
    if (polyfill.DataViewPolyfill.prototype[this.getter] == null) {
      throw new Error(`getter '${this.getter}' must be a DataView method`);
    }
    if (polyfill.DataViewPolyfill.prototype[this.setter] == null) {
      throw new Error(`setter '${this.setter}' must be a DataView method`);
    }
  }

  get(streamView, littleEndian) {
    const value = streamView.dataView[this.getter](streamView.byteOffset,
                                                   littleEndian);
    streamView.byteOffset += this.byteLength;
    return value;
  }

  set(streamView, value, littleEndian) {
    streamView.dataView[this.setter](streamView.byteOffset, value,
                                     littleEndian);
    streamView.byteOffset += this.byteLength;
  }
}


/**
* This is just like the uint8 codec, but get() returns true or false values.
*/
class BooleanCodec extends Codec {
  constructor() {
    super({byteLength: 1, getter: 'getUint8', setter: 'setUint8'});
  }

  get(streamView, littleEndian) {
    return super.get(streamView, littleEndian) ? true : false;
  }

  set(streamView, value, littleEndian) {
    super.set(streamView, value ? 1 : 0, littleEndian);
  }
}


/**
* This encodes an array of booleans as a length and set of bitflags. get()
* returns an array of booleans.
*/
class BooleanArrayCodec {
  constructor() {}

  getByteLength(values) {
    const length = (values && values.length) || 0;
    const valueBytes = Math.ceil(length / 8);
    const lengthBits = Math.floor(polyfill.log2(length)) + 1;
    const lengthBytes = Math.max(Math.ceil(lengthBits / 7), 1);
    return (lengthBytes + valueBytes) * _codecs.uint8.byteLength;
  }

  get(streamView, littleEndian) {
    let values = [];
    const length = this._getLength(streamView, littleEndian);
    const byteLength = Math.ceil(length / 8);
    let i = 0;
    for (let byteIndex = 0; byteIndex < byteLength; byteIndex++) {
      const byte = _codecs.uint8.get(streamView, littleEndian);
      for (let bit = 0; bit < 8 && i < length; bit++, i++) {
        values.push(((byte >> bit) & 1) ? true : false);
      }
    }
    return values;
  }

  set(streamView, values, littleEndian) {
    const length = (values && values.length) || 0;
    this._setLength(streamView, length, littleEndian);
    let byte = 0, bit = 0;
    for (let i = 0; i < length; i++, bit++) {
      if (bit === 8) {
        _codecs.uint8.set(streamView, byte, littleEndian);
        byte = 0;
        bit = 0;
      }
      byte |= (values[i] ? 1 : 0) << bit;
    }
    if (bit > 0) {
      _codecs.uint8.set(streamView, byte, littleEndian);
    }
  }

  _getLength(streamView, littleEndian) {
    let length = 0;
    for (let i = 0, byte = 128; (byte & 128) !== 0; i++) {
      byte = _codecs.uint8.get(streamView, littleEndian);
      length |= (byte & 127) << (i * 7);
    }
    return length;
  }

  _setLength(streamView, length, littleEndian) {
    if (length === 0) {
      _codecs.uint8.set(streamView, 0, littleEndian);
      return;
    }
    let remainder = length;
    while (remainder > 0) {
      let byte = remainder & 127;
      remainder >>= 7;
      if (remainder) {
        // There are still bits left, so indicate that the stream will have
        // another length byte by setting the high bit.
        byte |= 128;
      }
      _codecs.uint8.set(streamView, byte, littleEndian);
    }
  }
}


/**
* Encodes IEEE-754 floating point values. Only single and double precision
* are supported. Note that single precision values will end up getting
* rounded, because JavaScript only uses double precision.
*/
class FloatCodec extends Codec {
  constructor({byteLength}) {
    if (byteLength === 4) {
      super({
        byteLength: byteLength,
        getter: 'getFloat32',
        setter: 'setFloat32',
      });
    } else if (byteLength === 8) {
      super({
        byteLength: byteLength,
        getter: 'getFloat64',
        setter: 'setFloat64',
      });
    } else {
      throw new RangeError('byteLength must be 4 or 8 for floats');
    }
  }
}


/**
* Encodes integer values, both signed and unsigned. Note that set will clamp
* values that are out of range for the given type (e.g. >= 127 becomes 127 for
* a signed int8).
*/
class IntegerCodec extends Codec {
  constructor({byteLength, signed}) {
    const bitLength = byteLength * 8;
    let getter, setter, minValue, maxValue;
    if (signed) {
      minValue = -Math.pow(2, bitLength - 1);
      maxValue = Math.pow(2, bitLength - 1) - 1;
      getter = `getInt${bitLength}`;
      setter = `setInt${bitLength}`;
    } else {
      minValue = 0;
      maxValue = Math.pow(2, bitLength) - 1;
      getter = `getUint${bitLength}`;
      setter = `setUint${bitLength}`;
    }
    super({byteLength: byteLength, getter: getter, setter: setter});
    this.minValue = minValue;
    this.maxValue = maxValue;
  }

  set(streamView, value, littleEndian) {
    if (value < this.minValue) {
      value = this.minValue;
    } else if (value > this.maxValue) {
      value = this.maxValue;
    }
    super.set(streamView, value, littleEndian);
  }
}


/**
* The array codec is a special case. It wraps a simple codec, but prefixes
* it with a uint32 length value. It will first read the length, then read
* than many of the values from the stream.
*/
class ArrayCodec {
  constructor(valueCodec) {
    this.lengthCodec = _codecs.uint32;
    if (typeof valueCodec === 'string') {
      this.valueCodec = _codecs[valueCodec];
      if (!this.valueCodec) {
        throw new Error(`Invalid array value type '${valueCodec}'`);
      }
    } else {
      this.valueCodec = valueCodec;
    }
  }

  getByteLength(values) {
    if (!values || !values.length) {
      return 0;
    }
    if (this.valueCodec.byteLength != null) {
      // The value codec has a fixed byte length.
      return (this.lengthCodec.byteLength +
              (values.length * this.valueCodec.byteLength));
    } else {
      // The value codec has a dynamic byte lenth (e.g. an array of strings of
      // different lengths), so we need to get the size of each value on
      // the fly.
      let byteLength = this.lengthCodec.byteLength;
      for (let i = 0, il = values.length; i < il; i++) {
        byteLength += this.valueCodec.getByteLength(values[i]);
      }
      return byteLength;
    }
  }

  get(streamView, littleEndian) {
    // First read the number of elements, then read the elements
    const length = this.lengthCodec.get(streamView, littleEndian);
    if (length > 0) {
      let values = new Array(length);
      for (let index = 0; index < length; index++) {
        values[index] = this.valueCodec.get(streamView, littleEndian);
      }
      return values;
    } else {
      return [];
    }
  }

  set(streamView, values, littleEndian) {
    const length = (values && values.length) || 0;
    this.lengthCodec.set(streamView, length, littleEndian);
    if (length > 0) {
      for (let i = 0, il = values.length; i < il; i++) {
        this.valueCodec.set(streamView, values[i], littleEndian);
      }
    }
  }
}

/**
* The string codec is another special case. JavaScript strings are UTF-16,
* which doesn't encode very efficiently for network traffic. The codec first
* converts the strings to UTF-8, then converts that to a byte array. The
* byte array is prefixed with the length of the UTF-8 string.
*/
class StringCodec {

  constructor() {
    this.lengthCodec = _codecs.uint32;
    this.valueCodec = _codecs.uint8;
  }

  getByteLength(value) {
    // FIXME: This sucks, shouldn't need to encode strings twice.
    if (value) {
      value = utf8.encode(value);
    }
    return (this.lengthCodec.byteLength +
            (this.valueCodec.byteLength * value.length));
  }

  get(streamView, littleEndian) {
    // First read the number of characters, then the characters
    let length = this.lengthCodec.get(streamView, littleEndian);
    if (length > 0) {
      let string = '';
      for (let i = 0; i < length; i++) {
        string += String.fromCharCode(
          this.valueCodec.get(streamView, littleEndian));
      }
      // The string is in UTF-8 format, convert it back to UTF-16
      return utf8.decode(string);
    } else {
      return '';
    }
  }

  set(streamView, value, littleEndian) {
    if (value) {
      // Convert the string to UTF-8 to save space
      const utf8String = utf8.encode(value);
      this.lengthCodec.set(streamView, utf8String.length, littleEndian);
      for (let i = 0; i < utf8String.length; i++) {
        this.valueCodec.set(streamView, utf8String.charCodeAt(i), littleEndian);
      }
    } else {
      // Undefined or empty string, just send a zero length
      this.lengthCodec.set(streamView, 0, littleEndian);
    }
  }
}


// This is a set of codecs that can be used by fields to convert typed values
// into an array of bytes, and to convert those bytes back into values. Note
// that the "array" type does not have a codec in this object, because
// ArrayCodec objects are created on the fly as needed.
_codecs.boolean = new BooleanCodec();
_codecs.float32 = new FloatCodec({byteLength: 4});
_codecs.float64 = new FloatCodec({byteLength: 8});
_codecs.int8 = new IntegerCodec({byteLength: 1, signed: true});
_codecs.int16 = new IntegerCodec({byteLength: 2, signed: true});
_codecs.int32 = new IntegerCodec({byteLength: 4, signed: true});
_codecs.uint8 = new IntegerCodec({byteLength: 1, signed: false});
_codecs.uint16 = new IntegerCodec({byteLength: 2, signed: false});
_codecs.uint32 = new IntegerCodec({byteLength: 4, signed: false});

// Create these last, because they refer to the other codecs internally.
_codecs.booleanArray = new BooleanArrayCodec();
_codecs.string = new StringCodec();


/**
* A stream view is an abstraction around a data view and array buffer for
* reading and writing data while keeping track of a cursor position.
*/
class StreamView {
  constructor(dataView, arrayBuffer) {
    this.dataView = dataView;
    this.arrayBuffer = arrayBuffer;
    this.byteOffset = 0;
  }

  toArray() {
    let array = new Array(this.dataView.byteLength);
    for (let i = 0, il = this.dataView.byteLength; i < il; i++) {
      array[i] = this.dataView.getUint8(i);
    }
    return array;
  }

  toString() {
    let string = '';
    for (let i = 0, il = this.dataView.byteLength; i < il; i++) {
      string += String.fromCharCode(this.dataView.getUint8(i));
    }
    return string;
  }
}

/**
* Create a new stream view.
*
* @param {number} byteLength Number of bytes to allocate for the view.
* @returns {StreamView}
*/
StreamView.create = (byteLength) => {
  let arrayBuffer = new _config.ArrayBuffer(byteLength);
  let dataView = new _config.DataView(arrayBuffer);
  return new StreamView(dataView, arrayBuffer);
};

/**
* Create a stream view from a string.
*
* @param {string} string A string of encoded data.
* @returns {StreamView}
*/
StreamView.createFromString = (string) => {
  let codec = _codecs.uint8;
  let streamView = StreamView.create(string.length);
  for (let i = 0, il = string.length; i < il; i++) {
    codec.set(streamView, string.charCodeAt(i));
  }
  streamView.byteOffset = 0;
  return streamView;
};


/**
* Return true if the type is one of the allowed types.
*
* @param {string} type A type string, such as "array" or "uint8".
* @returns {boolean}
*/
function isValidType(type) {
  return _codecs.hasOwnProperty(type) || type === 'array';
}


/**
* Fields represent a single property in an object. These fields are grouped
* into definition objects.
*/
class Field {
  constructor({key, type, valueType}) {
    this.key = key;
    this.type = type;
    this.valueType = valueType;
    if (!this.key) {
      throw new Error('key is required');
    }
    if (!isValidType(this.type)) {
      throw new Error(`Invalid type '${this.type}'`);
    }
    if (this.type === 'array') {
      if (this.valueType === 'array' || this.valueType === 'string' ||
          !isValidType(this.valueType)) {
        throw new Error(`Invalid array value type '${this.valueType}'`);
      }
      this.codec = new ArrayCodec(this.valueType);
    } else {
      this.codec = _codecs[this.type];
    }
  }
}

/**
* Definitions are a grouping of fields, and are used to encode or decode an
* individual message. They can be grouped into schemas or used standalone.
*/
class Definition {
  constructor(fields, {id, key, littleEndian, delta} = {}) {
    this.fields = fields;
    this.id = id;
    this.key = key;
    this.littleEndian = littleEndian;
  }

  /**
  * Calculate the number of bytes required to encode the given object.
  *
  * @param {Object} object The object to be encoded.
  * @returns {number}
  */
  getByteLength(object) {
    if (this.byteLength != null) {
      return this.byteLength;
    }
    let byteLength = 0;
    let fixedByteLength = true;
    for (let i = 0, il = this.fields.length; i < il; i++) {
      const {key, codec} = this.fields[i];
      if (codec.byteLength != null) {
        byteLength += codec.byteLength;
      } else {
        byteLength += codec.getByteLength(object[key]);
        fixedByteLength = false;
      }
    }
    if (fixedByteLength) {
      // If all the fields had a fixed length, cache the definition's length.
      this.byteLength = byteLength;
    }
    return byteLength;
  }

  /**
  * Read an object from the given stream.
  *
  * @param {StreamView} streamView
  * @returns {Object}
  */
  get(streamView) {
    let values = {};
    for (let i = 0, il = this.fields.length; i < il; i++) {
      const {key, codec} = this.fields[i];
      values[key] = codec.get(streamView, this.littleEndian);
    }
    return values;
  }

  /**
  * Write an object into the given stream.
  *
  * @param {StreamView} streamView
  * @param {Object} object
  */
  set(streamView, object) {
    for (let i = 0, il = this.fields.length; i < il; i++) {
      const {key, codec} = this.fields[i];
      codec.set(streamView, object[key], this.littleEndian);
    }
  }

  /**
  * Read an object from the given string.
  *
  * @param {string} string
  * @returns {Object}
  */
  parse(string) {
    return this.get(StreamView.createFromString(string));
  }

  /**
  * Convert the given object into a string.
  *
  * @param {Object} object
  * @returns {string}
  */
  stringify(object) {
    let streamView = StreamView.create(this.getByteLength(object));
    this.set(streamView, object);
    return streamView.toString();
  }
}


/**
* A schema is a grouping of definitions. It allows you to encode packets
* by name, in a way that can be decoded automatically by a matching schema
* on the other end of a connection.
*
* Note that this assumes you won't have more than 255 packets, for now. If
* you need more than that, you can pass an idType: option to the constructor.
*/
class Schema {
  constructor({idType} = {}) {
    this.definitions = {};
    this.definitionsById = {};
    this.idType = idType || 'uint8';
    this.nextDefinitionId = 1;
  }

  define(key, fields) {
    const id = this.nextDefinitionId++;
    let definition = new Definition(fields.map((options) => {
      return new Field(options);
    }), {id: id, key: key});
    this.definitions[key] = definition;
    this.definitionsById[id] = definition;
    return definition;
  }

  parse(string) {
    let streamView = StreamView.createFromString(string);
    let idCodec = _codecs[this.idType];
    let id = idCodec.get(streamView);
    let definition = this.definitionsById[id];
    if (definition == null) {
      throw new Error(`'${id}' is not defined in schema`);
    }
    return {
      key: definition.key,
      data: definition.get(streamView),
    };
  }

  stringify(key, object) {
    let definition = this.definitions[key];
    if (definition == null) {
      throw new Error(`'${key}' is not defined in schema`);
    }
    let idCodec = _codecs[this.idType];
    let streamView = StreamView.create(idCodec.byteLength +
                                       definition.getByteLength(object));
    idCodec.set(streamView, definition.id);
    definition.set(streamView, object);
    return streamView.toString();
  }
}


/**
* Create a new Definition object.
*
* @param {Array.<{key: string, type: string, valueType: string}>} fields The
*   fields that make up the definition. These will be converted into {Field}
*   instances when constructing the definition.
* @returns {Definition}
*/
export function define(fields) {
  return new Definition(fields.map((options) => {
    return new Field(options);
  }));
}


/**
* Create a new Schema object.
*/
export function createSchema() {
  return new Schema();
}


export var _polyfill = polyfill;
export var _StreamView = StreamView;
