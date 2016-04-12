_          = require 'lodash'
redis      = require 'fakeredis'
Datastore  = require 'meshblu-core-datastore'
JobManager = require 'meshblu-core-job-manager'
mongojs    = require 'mongojs'
RedisNS    = require '@octoblu/redis-ns'
uuid       = require 'uuid'
EnqueueJobsForWebhooksBroadcastSent = require '../'

describe 'EnqueueJobsForWebhooksBroadcastSent', ->
  beforeEach (done) ->
    @datastore = new Datastore
      database: mongojs('meshblu-core-task-enqueue-jobs-for-webhooks-broadcast-sent')
      collection: 'devices'

    @datastore.remove done

  beforeEach ->
    @redisKey = uuid.v1()
    @jobManager = new JobManager
      client: new RedisNS 'ns', redis.createClient(@redisKey)
      timeoutSeconds: 1

  beforeEach ->
    client = new RedisNS 'ns', redis.createClient(@redisKey)
    @sut = new EnqueueJobsForWebhooksBroadcastSent {
      datastore:         @datastore
      jobManager:        new JobManager {client: client, timeoutSeconds: 1}
      uuidAliasResolver: {resolve: (uuid, callback) -> callback(null, uuid)}
    }

  describe '->do', ->
    context 'with a device with no webhooks', ->
      beforeEach (done) ->
        @datastore.insert {
          uuid: 'subscriber'
        }, done

      context 'when given a valid job', ->
        beforeEach (done) ->
          request =
            metadata:
              auth: {uuid: 'subscriber'}
              route: [{type: 'broadcast.sent', from: 'subscriber', to: 'subscriber'}]
              responseId: 'its-electric'
            rawData: '{}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

    context 'with a device with one webhooks', ->
      beforeEach (done) ->
        @datastore.insert {
          uuid: 'subscriber'
          meshblu:
            forwarders:
              broadcast:
                sent: [{
                  type:   'webhook'
                  url:    'https://google.com'
                  method: 'POST'
                }]
        }, done

      context 'when given a valid job', ->
        beforeEach (done) ->
          request =
            metadata:
              auth: {uuid: 'subscriber'}
              route: [{type: 'broadcast.sent', from: 'subscriber', to: 'subscriber'}]
              responseId: 'its-electric'
            rawData: '{}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        it 'should enqueue a job to deliver the webhook', (done) ->
          @jobManager.getRequest ['request'], (error, request) =>
            return done error if error?
            delete request?.metadata?.responseId
            expect(request).to.deep.equal {
              metadata:
                jobType: 'DeliverWebhook'
                auth:
                  uuid: 'subscriber'
                fromUuid: 'subscriber'
                toUuid: 'subscriber'
                messageType: 'broadcast.sent'
                route: [{type: "broadcast.sent", from: "subscriber", to: "subscriber"}]
                options:
                  type:   'webhook'
                  url:    'https://google.com'
                  method: 'POST'
              rawData: '{}'
            }
            done()

      context 'when given a valid job where the last hop from does not match the to', ->
        beforeEach (done) ->
          request =
            metadata:
              auth: {uuid: 'subscriber'}
              route: [{type: 'broadcast.sent', from: 'emitter', to: 'subscriber'}]
              responseId: 'its-electric'
            rawData: '{}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        it 'should enqueue a job to deliver the webhook', (done) ->
          @jobManager.getRequest ['request'], (error, request) =>
            return done error if error?
            delete request?.metadata?.responseId
            expect(request).to.deep.equal {
              metadata:
                jobType: 'DeliverWebhook'
                auth:
                  uuid: 'subscriber'
                fromUuid: 'subscriber'
                toUuid: 'subscriber'
                messageType: 'broadcast.sent'
                route: [{type: "broadcast.sent", from: "emitter", to: "subscriber"}]
                options:
                  type:   'webhook'
                  url:    'https://google.com'
                  method: 'POST'
              rawData: '{}'
            }
            done()
