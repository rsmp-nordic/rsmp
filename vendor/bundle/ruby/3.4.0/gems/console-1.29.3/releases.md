# Releases

## v1.29.3

  - Serialized output now uses `IO#write` with a single string to reduce the chance of interleaved output.

## v1.29.2

  - Always return `nil` from `Console::Filter` logging methods.

## v1.29.1

  - Fix logging `exception:` keyword argument when the value was not an exception.

## v1.29.0

  - Don't make `Kernel#warn` redirection to `Console.warn` the default behavior, you must `require 'console/warn'` to enable it.
  - Remove deprecated `Console::Logger#failure`.

### Consistent Handling of Exceptions

`Console.call` and all wrapper methods will now consistently handle exceptions that are the last positional argument or keyword argument. This means that the following code will work as expected:

``` ruby
begin
rescue => error
	# Last positional argument:
	Console.warn(self, "There may be an issue", error)
	
	# Keyword argument (preferable):
	Console.error(self, "There is an issue", exception: error)
end
```

## v1.28.0

  - Add support for `Kernel#warn` redirection to `Console.warn`.
