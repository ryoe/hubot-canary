# hubot-canary

A **[Hubot][hubot]** script to query the [canary.io API][canary].

[hubot]: https://github.com/github/hubot
[canary]: https://canary.io

## Install

Install with **npm** using ```--save``` to add to your ```package.json``` dependencies.
```
	> npm install --save hubot-canary
```

Then add **"hubot-canary"** to your ```external-scripts.json```.

Example external-scripts.json
```json
["hubot-canary"]
```

Or if you prefer, just drop **canary-io.coffee** in your **[Hubot][hubot] scripts** folder and enjoy.

## Use It

- **hubot canary check** - get the list of URLs which have measurements taken by [canary.io][canary] 
- **hubot canary check &lt;filter&gt;** - get filtered list of checked URLs. Coming soon!
- **hubot canary check reset** - clear the ```hubot canary check``` cache, then get again
- **hubot canary measure &lt;check-id&gt;** - get measurements of **check-id** for last 10 seconds
- **hubot canary measure &lt;check-id&gt; &lt;num-seconds&gt;** - get measurements of **check-id** for last **num-seconds** seconds
- **hubot canary help** - get list of ```hubot canary``` commands


##Improve It

Feel free to help this script suck less by opening issues and/or sending pull requests. 

If you haven't already, be sure to checkout the **[Hubot scripting guide](https://github.com/github/hubot/blob/master/docs/scripting.md)** for tons of info about extending **[Hubot][hubot]**.

## Coding Style

Other than the 79 character line length limit, which I consider to be a suggestion, let's try to follow the **[CoffeeScript Style Guide](https://github.com/polarmobile/coffeescript-style-guide)**.