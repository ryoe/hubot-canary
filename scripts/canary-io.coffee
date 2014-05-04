# Description:
#   A hubot script to query the canary.io API.
#
# Dependencies:
#   none
#
# Commands:
#   hubot canary check - get the list of URLs which have measurements taken by canary.io 
#   hubot canary check <filter> - get filtered list of checked URLs. Coming soon!
#   hubot canary check reset - clear the hubot canary check cache, then get again
#   hubot canary measure <check-id> - get measurements of <check-id> for last 10 seconds
#   hubot canary measure <check-id> <num-seconds> - get measurements of <check-id> for last <num-seconds> seconds
#   hubot canary help - get list of hubot canary commands
#
# Notes:
#   Have fun with it.
#
# Author:
#   ryoe

checks = []
checksUrl = 'http://checks.canary.io'
measuresUrl = 'https://api.canary.io/checks/XXX/measurements?range=YYY'

apiCall = (msg, url, cb) ->
  msg.http(url)
    .headers(Accept: 'application/json')
    .get() (err, res, body) ->
      if err
        cb err, ['error']
        return

      if res.statusCode == 200
        cb null, body
      else if res.statusCode == 301
        # get url from body
        # assumes body is <a href="redirUrl">Some text</a>
        matches = body.match(/href="(.*)"/i)
        redirUrl = matches[1]
        apiCall msg, redirUrl, cb
      else
        cb res.statusCode, body

getChecks = (msg) ->
  text = msg.message.text

  if text.match(/\breset\b/i)
    checks = []

  if checks.length > 0
    #use cached checks
    displayChecks msg
    return

  apiCall msg, checksUrl, (err, body) ->
    if err
      console.log err
      msg.send body
      return

    checks = JSON.parse body
    displayChecks msg

displayChecks = (msg) ->
  deets = []
  deets.push checkDetails c for c in checks
  msg.send deets.join '\n'

checkDetails = (check) ->
  return 'id: ' + check.id + ' => url: ' + check.url

getMeasurements = (msg) ->
  text = msg.message.text
  matches = text.match(/\bmeasure(ment)?(s)?\b \b(\S*)+\b(\s*)?(\d*)?/i)

  if not matches?
    getUnknownCommand msg
    return

  checkId = matches[3]
  range = matches[5] || 10

  #TODO: validate checkId

  regEx = new RegExp 'XXX', 'i'
  url = measuresUrl.replace regEx, checkId
  regEx = new RegExp 'YYY', 'i'
  url = url.replace regEx, range

  apiCall msg, url, (err, body) ->
    if err
      console.log err
      msg.send body
      return

    data = JSON.parse body
    displayMeasurements msg, data, checkId, range

displayMeasurements = (msg, measurements, checkId, range) ->
  if measurements.length == 0
    msg.send 'Zero measurements found for ' + checkId + ' in last ' + range + ' seconds.'
    return

  check = measurements[0].check

  deets = []
  deets.push measurements.length + ' measurements found for ' + check.url + ' in last ' + range + ' seconds.'
  deets.push '--------------------'
  deets.push measurementDetails m for m in measurements

  msg.send deets.join '\n'

measurementDetails = (measurement) ->
  deets = []
  deets.push 'id: ' + measurement.id
  deets.push 'timestamp: ' + measurement.t
  deets.push 'total time: ' + measurement.total_time
  deets.push 'connect time: ' + measurement.connect_time
  deets.push 'start transfer time: ' + measurement.starttransfer_time
  deets.push 'name lookup time: ' + measurement.namelookup_time
  deets.push 'location: ' + measurement.location
  deets.push 'exit status: ' + measurement.exit_status
  deets.push 'http status: ' + measurement.http_status
  deets.push 'local ip: ' + measurement.local_ip
  deets.push 'primary ip: ' + measurement.primary_ip
  deets.push '--------------------'

  return deets.join '\n'

getHelp = (msg) ->
  help = []
  help.push 'hubot canary check - get the list of URLs which have measurements taken by canary.io' 
  help.push 'hubot canary check <filter> - get filtered list of checked URLs. Coming soon!'
  help.push 'hubot canary check reset - clear the hubot canary check cache, then get again'
  help.push 'hubot canary measure <check-id> - get measurements of <check-id> for last 10 seconds'
  help.push 'hubot canary measure <check-id> <num-seconds> - get measurements of <check-id> for last <num-seconds> seconds'
  help.push 'hubot canary help - get list of hubot canary commands'

  msg.send help.join '\n'

getUnknownCommand = (msg) ->
  list = []
  list.push 'Unable to comply. Unknown command "' + msg.message.text + '"'
  list.push 'Try "hubot canary help".'

  msg.send list.join '\n'

module.exports = (robot) ->
  robot.respond /\bcanary\b/i, (msg) ->
    text = msg.message.text

    if text.match(/\bcheck(s)?\b/i)
      getChecks msg
    else if text.match(/\bhelp\b/i)
      getHelp msg
    else if text.match(/\bmeasure(ment)?(s)?\b/i)
      getMeasurements msg
    else
      getUnknownCommand msg
