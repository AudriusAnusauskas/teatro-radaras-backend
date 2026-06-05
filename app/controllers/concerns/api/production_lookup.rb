module Api::ProductionLookup
  extend ActiveSupport::Concern

  private

  def find_production_by_slug(slug, theater_slug: nil, includes: [])
    scope = Production.includes(includes)

    if theater_slug.present?
      scope.joins(:theater).where(theaters: { slug: theater_slug }).friendly.find(slug)
    else
      scope.friendly.find(slug)
    end
  end
end
