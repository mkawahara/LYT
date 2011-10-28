# A facade for `console.*` functions
@log = do ->
  console = window.console or {}
  
  # Error-checking alias for `console.log()`
  message: (messages...) ->
    return unless config.logging > 1
    console.log? messages...
  
  # Error-checking alias for `console.error()` (falls back to `console.log`)
  error: (messages...) ->
    return unless config.logging > 0
    method = console.error or console.log
    method?.apply console, messages
  
  # Error-checking alias for `console.info()` (falls back to `console.log`)
  info: (messages...) ->
    return unless config.logging > 1
    (console.info or @message).apply console, messages
  
  # Log a group of messages. By default, it'll try to call `console.groupCollapsed()` rather
  # than `console.group()`. If neither function exists, it'll fake it with `log.message`
  #
  # The first argument is the title of the group. If you pass more than 1 argument, 
  # the remaining arguments will each be logged inside the group by `log.message`, and
  # the group will be "closed" with `log.groupEnd`
  group: (title = "", messages...) ->
    return unless config.logging > 1
    method = console.groupCollapsed or console.group
    if method?
      method.call console, title
    else
      @message "=== #{title} ==="
    
    if messages.length > 0
      @message message for message in messages
      @closeGroup()
  
  # Same as `group` except 
  errorGroup: (title = "", messages...) ->
    return unless config.logging > 0
    method = console.groupCollapsed or console.group
    if method?
      method.call console, title
    else
      @error "=== #{title} ==="
    
    if messages.length > 0
      @error message for message in messages
      @closeGroup()
  
  # Closes an open group
  closeGroup: ->
    (console.groupEnd or @message).call console, "=== *** ==="
  
  # Error-checking alias for `console.trace`
  trace: ->
    return unless config.logging > 0
    console.trace?()
  
# ---------

# These 5 lines replace the 26-34 lines in `SecToTime` _and_ does type checking… I deserve a damn medal for that! :-)
@formatTime = (seconds) ->
  seconds = parseInt(seconds, 10)
  seconds = 0 if not seconds? or seconds < 0
  hours   = (seconds / 3600) >>> 0
  minutes = "0" + (((seconds % 3600 ) / 60) >>> 0)
  seconds = "0" + (seconds % 60)
  "#{hours}:#{minutes.slice -2}:#{seconds.slice -2}"

# Ok, so this one is actually a bit longer than the original in `SetTotalSeconds`, but it's way more robust and
# handles times both with and without the hour component (e.g. both "24:36" and "1:32:53")
@parseTime = (string) ->
  components = String(string).match /^(\d*):?(\d{2}):(\d{2})$/
  return 0 unless components?
  components.shift()
  # (Always use the radix argument for `parseInt`! Especially here, where `parseInt("08")` would return `0`, as "0*" is interpreted as octal, and 08 is meaningless in octal)
  components = (parseInt(component, 10) || 0 for component in components)
  components[0] * 3600 + components[1] * 60 + components[2]