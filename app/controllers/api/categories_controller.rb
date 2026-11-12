module Api
  # The user's categories. Transactions go only on categories without sub-categories (assignable).
  class CategoriesController < BaseController
    def index
      categories = Current.user.transaction_categories.includes(:children).order(:id)
      render json: { categories: categories.map { |category| category_json(category) } }
    end

    # Creates a category, never changes one: a name already taken is an error.
    def create
      name = params.require(:name)
      if Current.user.transaction_categories.exists?(name: name)
        return render_error("A category named #{name} already exists", :unprocessable_entity)
      end

      category = TransactionCategory.define!(name: name, kind: params[:kind].presence, parent: params[:parent].presence,
                                             description: params[:description].presence, user: Current.user)
      render json: category_json(category), status: :created
    end

    private

    def category_json(category)
      { id: category.id, name: category.name, kind: category.exclude_from_stats? ? "excluded" : category.kind,
        parent_id: category.parent_id, description: category.description, assignable: category.children.empty? }
    end
  end
end
