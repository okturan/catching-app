class DefaultEventDescriptionToBlank < ActiveRecord::Migration[8.1]
  # The description stops being required. The NOT NULL constraint stays, so the
  # column needs a default an omitted attribute can land on.
  def change
    change_column_default :events, :description, from: nil, to: ""
  end
end
