# A page may name itself with content_for :meta_title.
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
