module Scrapers
  class OktScheduleImporter < BaseScheduleImporter
    private

    def theater_slug
      "oskaro-korsunovo-teatras"
    end

    def city_for(data)
      data[:city]
    end
  end
end
