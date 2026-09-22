# The title and share card of every page. A page may name itself with
# content_for :meta_title; the description and the image are the site's.
module MetaTagsHelper
  def meta_title
    content_for(:meta_title) || t("meta.title")
  end

  def meta_description
    t("meta.description")
  end

  def meta_image
    image_url("cover.jpg")
  end
end
