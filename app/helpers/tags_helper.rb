module TagsHelper

  include Annotations

  def ann_cloud(tags, classes, counter_method=:count)
    tags = tags.sort_by{|t| t.text.downcase}

    max_count = tags.max_by(&:tag_count).tag_count.to_f
    if max_count < 1
      max_count = 1
    end

    tags.each do |tag|
      index = ((tag.tag_count / max_count) * (classes.size - 1)).round
      yield tag, classes[index]
    end
  end

  def fetch_tags_for_item object,attribute="tag"
    all_tags = TextValue.all_tags attribute
    item_tags = object.annotations.with_attribute_name(attribute).include_values.collect{|a| a.value}.uniq

    return all_tags,item_tags
  end

  def link_for_ann tag, options={}
    length=options[:truncate_length]
    length||=150
    link = show_ann_path(tag)

    text = tag.text

    link_to truncate(text,:length=>length), link, :class=>options[:class],:id=>options[:id],:style=>options[:style],:title=>tooltip_title_attrib(text)
  end

  def list_item_tags_list tags,options={}
    tags.map do |t|
      divider=tags.last==t ? "" : "<span class='spacer'>,</span> ".html_safe
      link_for_ann(t,options)+divider
    end.join("").html_safe
  end

end
