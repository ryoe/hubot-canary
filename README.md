# hubot-canary

A [Hubot][hubot] script to query the [canary.io API][canary].

[hubot]: https://github.com/github/hubot
[canary]: http://canary.io
[canary-gh]: https://github.com/canaryio
[ember]: http://emberjs.com/

## Volatility alert
The commands supported are subject to change with little warning as we figure out what **hubot-canary** will become.

## Install It

Install with **npm** using ```--save``` to add to your ```package.json``` dependencies.
```
  > npm install --save hubot-canary
```

Then add **"hubot-canary"** to your ```external-scripts.json```.

Example external-scripts.json
```json
["hubot-canary"]
```

Or if you prefer, just drop **canary-io.coffee** in your [Hubot][hubot] scripts folder and enjoy.

## Use It

- **hubot canary check** - get the list of URLs which have measurements taken by [canary.io][canary] 
- **hubot canary check &lt;filter&gt;** - get filtered list of checked URLs. Coming soon!
- **hubot canary check reset** - clear the ```hubot canary check``` cache, then get again
- **hubot canary measure &lt;check-id&gt;** - get url to download measurements of **check-id** for last 10 seconds
- **hubot canary measure &lt;check-id&gt; &lt;num-seconds&gt;** - get url to download measurements of **check-id** for last **num-seconds** seconds
- **hubot canary mon &lt;check-id&gt;** - start monitoring &lt;check-id&gt;. every 5 seconds send ```hubot canary summary <check-id>```
- **hubot canary mon stop &lt;check-id&gt;** - stop monitoring &lt;check-id&gt;
- **hubot canary mon stop all - stop all monitoring
- **hubot canary summary &lt;check-id&gt;** - get summary measurements of  &lt;check-id&gt; for last 5 minutes sorted by most http status 5xx, most failed checks (non-zero exit_status), slowest avg, slowest single call, slowest total time
- **hubot canary help** - get list of ```hubot canary``` commands


##Improve It

Feel free to help this script suck less by opening issues and/or sending pull requests. 

If you haven't already, be sure to checkout the [Hubot scripting guide](https://github.com/github/hubot/blob/master/docs/scripting.md) for tons of info about extending [Hubot][hubot].

## Coding Style

Other than the 79 character line length limit, which I consider to be a suggestion, let's try to follow the [CoffeeScript Style Guide](https://github.com/polarmobile/coffeescript-style-guide).

## Other Projects Consuming canary.io

- [canary-ember](https://github.com/jagthedrummer/canary-ember) - An [Ember][ember] front end to data produced by [canary.io][canary]

