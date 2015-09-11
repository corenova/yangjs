# REST/JSON interface feature module

This feature add-on module enables dynamic REST/JSON interface
generation based on available runtime `module` instances.

It utilizes the underlying [express](express.litcoffee) feature add-on
to dynamically create routing middleware and associates various HTTP
method facilities according to the available runtime `module`
instances.

## Source Code

    Forge = require '../yangforge'
    module.exports = Forge.Interface
      name: 'restjson'
      description: 'REST/JSON web services interface generator'
      needs: [ 'express' ]
      generator: (app) ->
        console.log "generating REST/JSON interface..."
        express = require 'express'

        self = this
        router = (->
          @all '*', (req, res, next) ->
            req.target ?= self
            next()

          @param 'target', (req, res, next, target) ->
            match = req.target.access? target
            if match? then req.target = match; next() else next 'route'

          @get '/', (req, res, next) ->
            #res.locals.result = Forge.objectify req.params.target, req.target.serialize()
            res.locals.result = req.target.serialize()
            next()

          return this
        ).call express.Router()

**Primary Module routing endpoint**

        console.log "generating Module Router..."
        moduleRouter = (->
          @route '/'
          .all (req, res, next) ->
            if (req.target.meta 'synth') is 'forge'
              console.log "Module: #{req.originalUrl}"
              next()
            else next 'route'
          .options (req, res, next) ->
            res.send
              REPORT:
                description: 'get detailed information about this module'
              GET:
                description: 'get serialized output for this module'
              PUT:
                description: 'update configuration for this module'
              COPY:
                description: 'get a copy of this module for cloning it elsewhere'
          .report (req, res, next) -> res.locals.result = req.target.report(); next()

          @param 'module', (req, res, next, module) ->
            match = req.target.access "modules.#{module}"
            if match? then req.target = match; next() else next 'route'

          @param 'container', (req, res, next, container) ->
            match = req.target.access "module.#{container}"
            if (match?.meta 'synth') in [ 'model', 'object', 'list' ]
              req.target = match; next()
            else next 'route'

          @use '/:module', router
          @use '/:container', router

          return this
        ).call express.Router()

**Active Data Model processing routing endpoint**

        console.log "generating Model Router..."
        modelRouter = (->
          @route '/'
          .all (req, res, next) ->
            if (req.target.meta 'synth') in [ 'forge', 'model' ]
              console.log "Model: #{req.originalUrl}"
              next()
            else next 'route'
          .put (req, res, next) ->
            (req.target.set req.body).save()
            .then (result) ->
              res.locals.result = req.target.serialize();
              next()
            .catch (err) ->
              req.target.rollback()
              next err

          @param 'action', (req, res, next, action) ->
            match = req.target.access "methods.#{action}"
            if match? then req.action = match; next() else next 'route'

          @route '/:action'
          .options (req, res, next) ->
            keys = Forge.Property.get 'options'
            keys.push 'description', 'reference', 'status'
            collapse = (obj) ->
              return obj unless obj instanceof Object
              for k, v of obj when k isnt 'meta'
                obj[k] = collapse v
              for k, v of obj.meta when k in keys
                obj[k] = v
              delete obj.meta
              return obj
            res.send
              POST: collapse req.action.meta.reduce()
          .post (req, res, next) ->
            console.info "restjson: invoking rpc operation '#{req.action.name}'".grey
            req.target.invoke req.action.name, req.body, req.target
              .then  (output) -> res.locals.result = output.get(); next()
              .catch (err) -> next err

          return this
        ).call express.Router()

**Object Container processing routing endpoint**

        console.log "generating Object Router..."
        objRouter = (->
          @route '/'
          .all (req, res, next) ->
            if (req.target.meta 'synth') is 'object'
              console.log "Object: #{req.originalUrl}"
              next()
            else next 'route'

          # Add any special logic for handling 'container' here

          return this
        ).call express.Router()

**List Collection processing routing endpoint**

        console.log "generating List Router..."
        listRouter = (->
          @route '/'
          .all (req, res, next) ->
            if (req.target.meta 'synth') is 'list'
              console.log "List: #{req.originalUrl}"
              next()
            else next 'route'
          .post (req, res, next) ->
            next "cannot add a new entry without data" unless req.body?
            req.target.push req.body

            model = req.target.seek synth: (v) -> v in [ 'model', 'forge' ]
            model.save()
            .then (result) ->
              res.locals.result = req.target.serialize()
              next()
            .catch (err) ->
              model.rollback()
              next err

          @delete '/:key', (req, res, next) ->
            req.target.remove req.params.key
            req.target.parent.save()
            .then (result) ->
              res.locals.result = result.serialize()
              next()
            .catch (err) ->
              req.target.parent.rollback()
              next err

          return this
        ).call express.Router()

**Main REST/JSON routing endpoint**

        router.use moduleRouter, modelRouter, objRouter, listRouter
        # Nested Loopback to itself if additional target in the URL
        router.use '/:target', router

        restjson = (->
          bp = require 'body-parser'
          @use bp.urlencoded(extended:true), bp.json(strict:true), (require 'passport').initialize()

          @use router, (req, res, next) ->
            # always send back contents of 'result' if available
            unless res.locals.result? then return next 'route'
            res.setHeader 'Expires','-1'
            res.send res.locals.result
            next()

          # default log successful transaction
          @use (req, res, next) ->
            #req.forge.log?.info query:req.params.id,result:res.locals.result,
            # 'METHOD results for %s', req.record?.name
            next()

          # default 'catch-all' error handler
          @use (err, req, res, next) ->
            console.error err
            res.status(500).send error: switch
              when err instanceof Error then err.toString()
              else JSON.stringify err

          return this
        ).call express.Router()

        if app?
          console.info "restjson: binding forgery to /restjson".grey
          app.use "/restjson", restjson

        return restjson
