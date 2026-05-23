class CommentSerializer
    def self.list(comment)
      {
        id: comment.id,
        body: comment.body,
        created_at: comment.created_at,
        user: {
          id: comment.user.id,
          name: comment.user.name,
          avatar_url: comment.user.avatar_url
        }
      }
    end
  end
