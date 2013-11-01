async = require 'async'
AWS = require 'aws-sdk'
colors = require 'colors'
jsdom = require 'jsdom'
fs = require 'fs'
path = require 'path'

LanguagesList = require './static-languages-list'

class Zapper
  bucket: ''
  prefix: ''
  
  htmlKey: 'index.html'

  html: ''
  languages: null

  options: null

  constructor: (options = {}) ->
    @[property] = value for property, value of options when property of @

    @htmlKey = "#{ @prefix }/#{ @htmlKey }" if 'prefix' of options

    AWS.config.update accessKeyId: @options.key if 'key' of options
    AWS.config.update secretAccessKey: @options.secret if 'secret' of options
    @s3 = new AWS.S3

  # Get available languages
  getAvailableLanguages: (cb) =>
    # Short circuit if languages were passed in manually.
    if @languages then cb()

    @languages = {}

    @s3.listObjects
      Bucket: @bucket
      Prefix: @prefix + '/translations'
      (err, { Contents }) =>
        if err
          console.log err, 'Error grabbing available languages.'.red
          cb null, true
          return

        for { Key } in Contents
          for code, name of LanguagesList when code is path.basename Key, path.extname Key
            @languages[code] = name

        cb()

  getHtml: (cb) =>
    @s3.getObject
      Bucket: @bucket
      Key: @htmlKey
      (err, { Body }) =>
        if err
          console.log 'Error fetching html.'.red
          cb null, true
          return

        @html = Body.toString()
        cb()

  modifyHtml: (cb) =>
    jsdom.env @html, (err, window) =>
      if err
        console.log 'Error creating jsdom environment.'.red
        cb null, true
        return

      { document } = window

      # Start fresh each time
      dataEls = document.querySelectorAll "script[id^=define-zooniverse-languages]"
      dataEls[i]?.parentNode.removeChild(dataEls[i]) for i in [0..dataEls.length - 1]

      scriptTag = document.createElement 'script'
      scriptTag.setAttribute 'type', 'text/javascript'
      scriptTag.id = "define-zooniverse-languages"
      scriptTag.innerHTML = "window.DEFINE_ZOONIVERSE_LANGUAGES = #{ JSON.stringify @languages }"

      firstScript = document.body.querySelector('script')

      if firstScript
        document.body.insertBefore scriptTag, firstScript
      else
        document.head.insertBefore scriptTag, document.head.firstChild

      @html = "<!DOCTYPE html>\n" + document.documentElement.outerHTML
      cb()

  uploadHtml: (cb) =>
    @s3.putObject
      Bucket: @bucket
      Key: @htmlKey
      ACL: "public-read"
      Body: new Buffer @html
      ContentType: "text/html"
      (err, s3Res) =>
        if err
          console.log 'Error uploading html.'.red
          cb null, true
          return

        cb()

  # Grab available languages from S3, insert list as JS variable onto page.
  go: =>
    async.series [@getHtml, @getAvailableLanguages, @modifyHtml, @uploadHtml], (err, results) =>
      if err
        console.log 'Error occurred while running zapper.'.red
      else
        console.log 'Success running zapper.'.green

module.exports = Zapper
