module Scrapers
  module TheaterScraperRegistry
    # Each entry: a theater with its catalog and schedule scraper/importer pairs.
    # Adding a theater = add one entry here.
    ENTRIES = [
      {
        key: "lndt",
        name: "Lietuvos nacionalinis dramos teatras",
        catalog: { scraper: Scrapers::LndtCatalogScraper, importer: Scrapers::LndtCatalogImporter },
        schedule: { scraper: Scrapers::LndtScheduleScraper, importer: Scrapers::LndtScheduleImporter }
      },
      {
        key: "jaunimo_teatras",
        name: "Valstybinis jaunimo teatras",
        catalog: { scraper: Scrapers::JaunimoTeatrasCatalogScraper, importer: Scrapers::JaunimoTeatrasCatalogImporter },
        schedule: { scraper: Scrapers::JaunimoTeatrasScheduleScraper, importer: Scrapers::JaunimoTeatrasScheduleImporter }
      },
      {
        key: "vmt",
        name: "Valstybinis Vilniaus mažasis teatras",
        catalog: { scraper: Scrapers::VmtCatalogScraper, importer: Scrapers::VmtCatalogImporter },
        schedule: { scraper: Scrapers::VmtScheduleScraper, importer: Scrapers::VmtScheduleImporter }
      },
      {
        key: "okt",
        name: "OKT / Vilniaus miesto teatras",
        catalog: { scraper: Scrapers::OktCatalogScraper, importer: Scrapers::OktCatalogImporter },
        schedule: { scraper: Scrapers::OktScheduleScraper, importer: Scrapers::OktScheduleImporter }
      },
      {
        key: "kauno_dramos",
        name: "Nacionalinis Kauno dramos teatras",
        catalog: { scraper: Scrapers::KaunoCatalogScraper, importer: Scrapers::KaunoCatalogImporter },
        schedule: { scraper: Scrapers::KaunoScheduleScraper, importer: Scrapers::KaunoScheduleImporter }
      }
    ].freeze

    def self.entries = ENTRIES

    def self.catalog_entries
      ENTRIES.select { |e| e[:catalog] }
    end

    def self.schedule_entries
      ENTRIES.select { |e| e[:schedule] }
    end
  end
end
