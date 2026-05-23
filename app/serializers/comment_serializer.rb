class CommentSerializer
    # user_rating: optional UserRating instance for this comment's author + production
    def self.list(comment, user_rating = nil)
      {
        id:         comment.id,
        body:       comment.body,
        created_at: comment.created_at.iso8601,
        user: {
          id:         comment.user.id,
          name:       comment.user.name,
          avatar_url: comment.user.avatar_url
        },
        user_rating: user_rating&.rating
      }
    end
  end
