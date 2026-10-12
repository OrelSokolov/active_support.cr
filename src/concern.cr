# ActiveSupport::Concern — Rails Concern semantics on Crystal macros.
#
#   module Timestamps
#     include ActiveSupport::Concern
#
#     class_methods do
#       def latest : self?
#         all.order(created_at: :desc).first
#       end
#     end
#
#     macro included
#       extend_class_methods!
#       property created_at : Time = Time.utc
#     end
#   end
#
# Documented deviation (Crystal hook macros accept no parameters, so
# Rails' `included do ... end` block syntax is not portable): concerns
# declare `macro included` directly — it expands in the body of the
# including type exactly like the Rails included-block. Call
# `extend_class_methods!` inside it to attach the concern's
# ClassMethods (no-op when the concern has none).

module ActiveSupport
  module Concern
    # No-op overridden by class_methods below for concerns that have them.
    macro extend_class_methods!
    end

    macro class_methods(&block)
      module ClassMethods
        {{ block.body }}
      end

      # Bakes the concern's own path into the generated hook helper.
      macro extend_class_methods!
        extend {{ @type }}::ClassMethods
      end
    end
  end
end
