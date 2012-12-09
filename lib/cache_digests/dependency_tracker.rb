module CacheDigests
  class DependencyTracker
    @trackers = Hash.new

    def self.find_dependencies(name, template)
      @trackers.fetch(template.handler).call(name, template)
    end

    def self.register_tracker(handler, tracker)
      @trackers[handler] = tracker
    end

    def self.unregister_tracker(handler)
      @trackers.delete(handler)
    end

    class ErbTracker
      EXPLICIT_DEPENDENCY = /# Template Dependency: (\S+)/

      # Matches:
      #   render partial: "comments/comment", collection: commentable.comments
      #   render "comments/comments"
      #   render 'comments/comments'
      #   render('comments/comments')
      #
      #   render(@topic)         => render("topics/topic")
      #   render(topics)         => render("topics/topic")
      #   render(message.topics) => render("topics/topic")
      RENDER_DEPENDENCY = /
        render\s*                     # render, followed by optional whitespace
        \(?                           # start an optional parenthesis for the render call
        (partial:|:partial\s+=>)?\s*  # naming the partial, used with collection -- 1st capture
        ([@a-z"'][@a-z_\/\."']+)      # the template name itself -- 2nd capture
      /x

      def self.call(name, template)
        new(name, template).dependencies
      end

      def initialize(name, template)
        @name, @template = name, template
      end

      def dependencies
        render_dependencies + explicit_dependencies
      rescue ActionView::MissingTemplate
        [] # File doesn't exist, so no dependencies
      end

      private
        attr_reader :name, :template

        def source
          template.source
        end
        
        def directory
          name.split("/")[0..-2].join("/")
        end

        def render_dependencies
          source.scan(RENDER_DEPENDENCY).
            collect(&:second).uniq.

            # render(@topic)         => render("topics/topic")
            # render(topics)         => render("topics/topic")
            # render(message.topics) => render("topics/topic")
            collect { |name| name.sub(/\A@?([a-z]+\.)*([a-z_]+)\z/) { "#{$2.pluralize}/#{$2.singularize}" } }.

            # render("headline") => render("message/headline")
            collect { |name| name.include?("/") ? name : "#{directory}/#{name}" }.
            
            # replace quotes from string renders
            collect { |name| name.gsub(/["']/, "") }
        end

        def explicit_dependencies
          source.scan(EXPLICIT_DEPENDENCY).flatten.uniq
        end
    end

    register_tracker(:erb, ErbTracker)
  end
end
