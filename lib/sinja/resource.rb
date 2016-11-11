# frozen_string_literal: true
require 'sinatra/base'
require 'sinatra/namespace'

require 'sinja/helpers/relationships'
require 'sinja/relationship_routes/has_many'
require 'sinja/relationship_routes/has_one'
require 'sinja/resource_routes'

module Sinja
  module Resource
    def def_action_helper(action, context=nil)
      abort "JSONAPI resource actions can't be HTTP verbs!" \
        if Sinatra::Base.respond_to?(action)

      context.define_singleton_method(action) do |**opts, &block|
        can(action, opts[:roles]) if opts.key?(:roles)

        if block.nil?
          if respond_to?(action)
            # TODO: Is this safe?
            remove_method(action)
            return
          else
            # TODO: Throw an error?
          end
        end

        define_method(action) do |*args|
          result =
            begin
              instance_exec(*args.take(block.arity.abs), &block)
            rescue Exception=>e
              halt 409, e.message if settings._sinja.conflict?(action, e.class)
              #halt 422, resource.errors if settings._sinja.invalid?(action, e.class) # TODO
              #not_found if settings._sinja.not_found?(action, e.class) # TODO
              raise
            end

          # TODO: Move this to a constant or configurable?
          required_arity = {
            :create=>2,
            :index=>-1,
            :fetch=>-1
          }.freeze[action] || 1

          case result
          when Array
            opts = {}
            if Hash === result.last
              opts = result.pop
            elsif required_arity < 0 && !(Array === result.first)
              result = [result]
            end

            raise ActionHelperError, "Unexpected return value(s) from `#{action}' action helper" \
              unless result.length == required_arity.abs

            result.push(opts)
          when Hash
            Array.new(required_arity.abs).push(result)
          else
            [result, nil].take(required_arity.abs).push({})
          end
        end
      end
    end

    def def_action_helpers(actions, context=nil)
      [*actions].each { |action| def_action_helper(action, context) }
    end

    def self.registered(app)
      app.helpers Helpers::Relationships do
        attr_accessor :resource

        def sanity_check!(id=nil)
          halt 409, 'Resource type in payload does not match endpoint' \
            if data[:type] != request.path.split('/').last # TODO

          halt 409, 'Resource ID in payload does not match endpoint' \
            if id && data[:id].to_s != id.to_s
        end
      end

      app.register ResourceRoutes
    end

    %i[has_one has_many].each do |rel_type|
      define_method(rel_type) do |rel, &block|
        rel_path = rel.to_s.tr('_', '-')

        namespace %r{/(?<resource_id>[^/]+)(?<r>/relationships)?/#{rel_path}}, :actions=>:show do
          helpers do
            def relationship_link?
              !params[:r].nil?
            end

            def resource
              super || self.resource = show(params[:resource_id]).first
            end

            def sanity_check!
              super(params[:resource_id])
            end

            define_method(:linkage) do
              # TODO: This is extremely wasteful. Refactor JAS to expose the linkage serializer?
              serialize_model(resource, :include=>rel_path)['data']['relationships'][rel_path]
            end
          end

          before do
            not_found 'Parent resource not found' unless resource
          end

          get '' do
            pass unless relationship_link?

            serialize_linkage
          end

          register RelationshipRoutes.const_get \
            rel_type.to_s.split('_').map(&:capitalize).join.to_sym

          if rel_type == :has_one
            pluck { resource.send(rel) }
          elsif rel_type == :has_many
            fetch { resource.send(rel) }
          end

          instance_eval(&block) if block
        end
      end
    end
  end
end