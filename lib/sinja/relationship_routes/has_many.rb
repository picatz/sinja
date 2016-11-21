# frozen_string_literal: true
module Sinja
  module RelationshipRoutes
    module HasMany
      ACTIONS = %i[fetch clear merge subtract].freeze
      CONFLICT_ACTIONS = %i[merge].freeze

      def self.registered(app)
        app.def_action_helpers(ACTIONS, app)

        app.head '' do
          unless relationship_link?
            allow :get=>:fetch
          else
            allow :get=>:itself, :patch=>[:clear, :merge], :post=>:merge, :delete=>:subtract
          end
        end

        app.get '' do
          pass unless relationship_link?

          serialize_linkage
        end

        app.get '', :actions=>:fetch do
          serialize_models(*fetch)
        end

        app.patch '', :nullif=>proc(&:empty?), :actions=>:clear do
          serialize_linkages?(*clear)
        end

        app.patch '', :actions=>%i[clear merge] do
          clear_updated, clear_opts = clear
          merge_updated, merge_opts = merge(data)
          serialize_linkages?(clear_updated||merge_updated, clear_opts.merge(merge_opts)) # TODO: DWIM?
        end

        app.post '', :actions=>%i[merge] do
          serialize_linkages?(*merge(data))
        end

        app.delete '', :actions=>%i[subtract] do
          serialize_linkages?(*subtract(data))
        end
      end
    end
  end
end
