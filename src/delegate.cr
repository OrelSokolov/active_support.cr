# delegate — Rails `delegate :name, to: :user` (macro on Object).
#
# P0 limitation: forwards positional args only. Crystal marks a generated
# `def m(*args, &block)` that forwards `&block` to a blockless target as
# block-required at every call site ("expected to be invoked with a
# block"), so block/named-arg forwarding is off until that quirk has a
# clean workaround.

class Object
  macro delegate(*methods, to = nil, prefix = nil, allow_nil = false)
    {% raise "delegate: missing `to:` target" unless to %}
    {% method_prefix = (prefix == true ? "#{to.id}_" : (prefix ? "#{prefix.id}_" : "")).id %}
    {% for method in methods %}
      {% if allow_nil %}
        def {{ method_prefix }}{{ method.id }}(*args)
          if (target = {{ to.id }}).nil?
            nil
          else
            target.{{ method.id }}(*args)
          end
        end
      {% else %}
        def {{ method_prefix }}{{ method.id }}(*args)
          {{ to.id }}.{{ method.id }}(*args)
        end
      {% end %}
    {% end %}
  end
end
