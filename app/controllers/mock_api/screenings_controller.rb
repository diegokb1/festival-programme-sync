module MockApi
  # Stands in for the third-party festival-management API. It is deliberately a
  # plain API controller with no shared auth or layout — a real external service
  # wouldn't share those with our app. It serves the in-memory fixtures from
  # MockApi::Dataset; it never touches our local database.
  class ScreeningsController < ActionController::API
    # GET /mock_api/screenings
    #   ?page=N          25 records per page
    #   ?generation=1|2  which fixture dataset to serve
    #   ?fail_after=N    serve N records across pages, then 500 on the next page
    #   ?slow=true       add a six-second delay before responding
    def index
      sleep 6 if truthy?(params[:slow])

      all    = Dataset.records(generation: params.fetch(:generation, 1))
      page   = [params.fetch(:page, 1).to_i, 1].max
      offset = (page - 1) * Dataset::PER_PAGE

      fail_after = params[:fail_after].presence&.to_i

      # We've already handed out `fail_after` records on earlier pages: blow up.
      if fail_after && offset >= fail_after
        return render json: { error: "Upstream festival system unavailable" },
                      status: :internal_server_error
      end

      slice = all[offset, Dataset::PER_PAGE] || []

      # Truncate the final successful page so exactly `fail_after` records escape.
      if fail_after
        allowed = [fail_after - offset, 0].max
        slice   = slice.first(allowed)
      end

      render json: {
        page:        page,
        per_page:    Dataset::PER_PAGE,
        total_pages: (all.size.to_f / Dataset::PER_PAGE).ceil,
        total_count: all.size,
        screenings:  slice
      }
    end

    private

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
