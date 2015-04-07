util = require 'util'
stream = require 'stream'

bufferTrim = require 'buffertrim'

Ascii = require './Ascii'
Binary = require './Binary'
Polygon = require './Polygon'
Vector = require './Vector'


class BinaryParser extends stream.Transform
	constructor: (@options = {}) ->
		@options.writableObjectMode ?= false
		@options.readableObjectMode ?= true
		@options.format ?= 'jsonl'
		super @options

		@internalBuffer = new Buffer(0)
		@header = ''
		@facesCounter = 0
		@countedFaces = 0
		@cursor = 80
		@currentModel = {}
		@currentFace = {}

		# File-structure:
		#
		# | header (80 * UInt8) |
		# | facesCounter (1 * UInt32) |
		#
		# face (50 Byte)
		# | normal (3 * Float) |
		# | vertex 1 (3 * Float) |
		# | vertex 2 (3 * Float) |
		# | vertex 3 (3 * Float) |
		# | attribute 3 (1 * UInt16) |
		#
		# | … |

		@headerByteCount = 80
		@vertexByteCount = 12
		@attributeByteCount = 2
		@facesCounterByteCount = 4
		@faceByteCount = 50
		@facesOffset = @headerByteCount + @facesCounterByteCount
		@coordinateByteCount = 4


	_flush: (done) =>
		if @facesCounter isnt @countedFaces
			@emit 'warning', "Number of specified faces (#{@facesCounter}) and
                counted number of faces (#{@countedFaces}) do not match"

		if @options.format is 'json'
			@push @currentModel
			done null, @internalBuffer
		else
			done null, @internalBuffer


	_transform: (chunk, encoding, done) ->
		@internalBuffer = Buffer.concat [@internalBuffer, chunk]

		while @cursor <= @internalBuffer.length

			if @cursor is @headerByteCount
				@header = bufferTrim.trimEnd(
					@internalBuffer.slice(0, @headerByteCount)
				).toString()
				@currentModel.name = @header

				if @options.format is 'json'
					@currentModel.faces = []
				else
					@push @currentModel

				@cursor += @facesCounterByteCount
				continue

			if @cursor is @facesOffset
				@facesCounter = @internalBuffer.readUInt32LE @headerByteCount
				@cursor += @faceByteCount
				continue

			if @cursor = (@facesOffset + (@countedFaces + 1) * @faceByteCount)
				@cursor -= @faceByteCount
				@currentFace = {
					normal: {
						x: @internalBuffer.readFloatLE(
							@cursor
						)
						y: @internalBuffer.readFloatLE(
							@cursor += @coordinateByteCount
						)
						z: @internalBuffer.readFloatLE(
							@cursor += @coordinateByteCount
						)
					}
				}

				@currentFace.vertices = []

				for i in [0..2]
					@currentFace.vertices.push {
						x: @internalBuffer.readFloatLE(
							@cursor += @coordinateByteCount
						)
						y: @internalBuffer.readFloatLE(
							@cursor += @coordinateByteCount
						)
						z: @internalBuffer.readFloatLE(
							@cursor += @coordinateByteCount
						)
					}

				@currentFace.attribute = @internalBuffer
					.readUInt16LE @cursor += @coordinateByteCount

				@cursor += @attributeByteCount

				if @options.format is 'json'
					@currentModel.faces.push @currentFace
				else
					@push @currentFace

				@cursor += @faceByteCount
				@countedFaces++

		done()


module.exports = BinaryParser
