class Api::ScreeningsController < Api::BaseController
  def index
    screenings = Screening.where("starts_at >= ?", Time.current)
                          .joins(:production)
                          .where(productions: { status: "active" })
                          .includes(production: [:theater, :director, :reviews])
                          .order(:starts_at)
    screenings = apply_filters(screenings, params)

    render json: {
      screenings: screenings.map { |s| ScreeningSerializer.list(s) },
      count: screenings.size
    }
  end

  private

  def apply_filters(scope, params)
    scope = scope.where("starts_at <= ?", params[:until]) if params[:until].present?
    scope = scope.joins(production: :theater)
                 .where(theaters: { city: params[:city] }) if params[:city].present?
    scope
  end
end
