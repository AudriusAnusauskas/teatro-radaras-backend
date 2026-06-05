module Scrapers
  class LndtScheduleImporter < BaseScheduleImporter
    private

    def url_key
      :production_source_url
    end

    def slug_key
      nil
    end

    def theater_slug
      nil
    end

    def city_for(data)
      data[:city]
    end
  end
end
