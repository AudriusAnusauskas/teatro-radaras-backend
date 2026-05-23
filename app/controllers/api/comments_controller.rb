class Api::CommentsController < Api::BaseController
    before_action :authenticate_user!
  
    def create
      production = Production.friendly.find(params[:production_slug])
      comment = production.comments.build(user: current_user, body: params[:body])
  
      if comment.save
        render json: { comment: CommentSerializer.list(comment) }, status: :created
      else
        render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
      end
    end
  
    def destroy
      comment = Comment.find(params[:id])
  
      return render_forbidden unless comment.user_id == current_user.id || current_user.admin?
  
      comment.update!(status: "removed", hidden_at: Time.current)
      head :no_content
    end
  
    private
  
    def render_forbidden
      render json: { error: "forbidden" }, status: :forbidden
    end
  end
