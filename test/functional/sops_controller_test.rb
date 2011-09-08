require 'test_helper'

class SopsControllerTest < ActionController::TestCase

  fixtures :all

  include AuthenticatedTestHelper
  include RestTestCases
  include SharingFormTestHelper

  def setup
    WebMock.allow_net_connect!
    login_as(:quentin)
    @object=sops(:downloadable_sop)
  end

  def test_get_xml_specific_version
    login_as(:owner_of_my_first_sop)
    get :show, :id=>sops(:downloadable_sop), :version=>2, :format=>"xml"
    perform_api_checks
    xml          =@response.body
    document     = LibXML::XML::Document.string(xml)
    version_node = document.find_first("//ns:version", "ns:http://www.sysmo-db.org/2010/xml/rest")
    assert_not_nil version_node
    assert_equal "2", version_node.content
    content_blob_node = document.find_first("//ns:blob", "ns:http://www.sysmo-db.org/2010/xml/rest")
    assert_not_nil content_blob_node
    md5sum=content_blob_node.find_first("//ns:md5sum", "ns:http://www.sysmo-db.org/2010/xml/rest").content

    #now check version 1
    get :show, :id=>sops(:downloadable_sop), :version=>1, :format=>"xml"
    perform_api_checks
    xml          =@response.body
    document     = LibXML::XML::Document.string(xml)
    version_node = document.find_first("//ns:version", "ns:http://www.sysmo-db.org/2010/xml/rest")
    assert_not_nil version_node
    assert_equal "1", version_node.content
    content_blob_node = document.find_first("//ns:blob", "ns:http://www.sysmo-db.org/2010/xml/rest")
    assert_not_nil content_blob_node
    md5sum2=content_blob_node.find_first("//ns:md5sum", "ns:http://www.sysmo-db.org/2010/xml/rest").content
    assert_not_equal md5sum, md5sum2

  end

  test 'creators show in list item' do
    p1=Factory :person
    p2=Factory :person
    sop=Factory(:sop,:title=>"ZZZZZ",:creators=>[p2],:contributor=>p1.user,:policy=>Factory(:public_policy, :access_type=>Policy::VISIBLE))

    get :index,:page=>"Z"

    #check the test is behaving as expected:
    assert_equal p1.user,sop.contributor
    assert sop.creators.include?(p2)
    assert_select ".list_item_title a[href=?]",sop_path(sop),"ZZZZZ","the data file for this test should appear as a list item"

    #check for avatars
    assert_select ".list_item_avatar" do
      assert_select "a[href=?]",person_path(p2) do
        assert_select "img"
      end
      assert_select "a[href=?]",person_path(p1) do
        assert_select "img"
      end
    end
  end

  test "request file button visibility when logged in and out" do

    sop = Factory :sop,:policy => Factory(:policy, :sharing_scope => Policy::EVERYONE, :access_type => Policy::VISIBLE)

    assert !sop.can_download?, "The SOP must not be downloadable for this test to succeed"

    get :show, :id => sop
    assert_response :success
    assert_select "#request_resource_button > a",:text=>/Request SOP/,:count=>1

    logout
    get :show, :id => sop
    assert_response :success
    assert_select "#request_resource_button > a",:text=>/Request SOP/,:count=>0
  end

  test "fail gracefullly when trying to access a missing sop" do
    get :show,:id=>99999
    assert_redirected_to sops_path
    assert_not_nil flash[:error]
  end

  test "should not create sop with file url" do
    file_path=File.expand_path(__FILE__) #use the current file
    file_url ="file://"+file_path
    uri      =URI.parse(file_url)

    assert_no_difference('Sop.count') do
      assert_no_difference('ContentBlob.count') do
        post :create, :sop => {:title=>"Test", :data_url=>uri.to_s}, :sharing=>valid_sharing
      end
    end
    assert_not_nil flash[:error]
  end

  def test_title
    get :index
    assert_select "title", :text=>/The Sysmo SEEK SOPs.*/, :count=>1
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:sops)
  end

  test "shouldn't show hidden items in index" do
    login_as(:aaron)
    get :index, :page => "all"
    assert_response :success
    assert_equal assigns(:sops).sort_by(&:id), Authorization.authorize_collection("view", assigns(:sops), users(:aaron)).sort_by(&:id), "sops haven't been authorized properly"
  end

  test "should get new" do
    get :new
    assert_response :success
    assert_select "h1", :text=>"New SOP"
  end

  test "should correctly handle bad data url" do
    sop={:title=>"Test", :data_url=>"http:/sdfsdfds.com/sdf.png",:projects=>[projects(:sysmo_project)]}
    assert_no_difference('Sop.count') do
      assert_no_difference('ContentBlob.count') do
        post :create, :sop => sop, :sharing=>valid_sharing
      end
    end
    assert_not_nil flash.now[:error]

    #not even a valid url
    sop={:title=>"Test", :data_url=>"s  df::sd:dfds.com/sdf.png",:projects=>[projects(:sysmo_project)]}
    assert_no_difference('Sop.count') do
      assert_no_difference('ContentBlob.count') do
        post :create, :sop => sop, :sharing=>valid_sharing
      end
    end
    assert_not_nil flash.now[:error]
  end

  test "should not create invalid sop" do
    sop={:title=>"Test",:projects=>[projects(:sysmo_project)]}
    assert_no_difference('Sop.count') do
      assert_no_difference('ContentBlob.count') do
        post :create, :sop => sop, :sharing=>valid_sharing
      end
    end
    assert_not_nil flash.now[:error]
  end

  test "associates assay" do
    login_as(:owner_of_my_first_sop) #can edit assay_can_edit_by_my_first_sop_owner
    s = sops(:my_first_sop)
    original_assay = assays(:assay_can_edit_by_my_first_sop_owner1)
    asset_ids = original_assay.related_asset_ids 'Sop'
    assert asset_ids.include? s.id

    new_assay=assays(:assay_can_edit_by_my_first_sop_owner2)
    new_asset_ids = new_assay.related_asset_ids 'Sop'
    assert !new_asset_ids.include?(s.id)

    put :update, :id => s.id, :sop =>{}, :assay_ids=>[new_assay.id.to_s]

    assert_redirected_to sop_path(s)

    s.reload
    original_assay.reload
    new_assay.reload

    assert !original_assay.related_asset_ids('Sop').include?(s.id)
    assert new_assay.related_asset_ids('Sop').include?(s.id)
  end

  test "should create sop" do
    login_as(:owner_of_my_first_sop) #can edit assay_can_edit_by_my_first_sop_owner
    assay=assays(:assay_can_edit_by_my_first_sop_owner1)
    assert_difference('Sop.count') do
      assert_difference('ContentBlob.count') do
        post :create, :sop => valid_sop, :sharing=>valid_sharing, :assay_ids => [assay.id.to_s]
      end
    end

    assert_redirected_to sop_path(assigns(:sop))
    assert_equal users(:owner_of_my_first_sop), assigns(:sop).contributor

    assert assigns(:sop).content_blob.url.blank?
    assert !assigns(:sop).content_blob.data_io_object.read.nil?
    assert assigns(:sop).content_blob.file_exists?
    assert_equal "file_picture.png", assigns(:sop).original_filename
    assay.reload
    assert assay.related_asset_ids('Sop').include? assigns(:sop).id
  end

  def test_missing_sharing_should_default_to_private
    assert_difference('Sop.count') do
      assert_difference('ContentBlob.count') do
        post :create, :sop => valid_sop
      end
    end
    assert_redirected_to sop_path(assigns(:sop))
    assert_equal users(:quentin), assigns(:sop).contributor
    assert assigns(:sop)

    sop            =assigns(:sop)
    private_policy = policies(:private_policy_for_asset_of_my_first_sop)
    assert_equal private_policy.sharing_scope, sop.policy.sharing_scope
    assert_equal private_policy.access_type, sop.policy.access_type
    assert_equal private_policy.use_whitelist, sop.policy.use_whitelist
    assert_equal private_policy.use_blacklist, sop.policy.use_blacklist
    assert sop.policy.permissions.empty?

    #check it doesn't create an error when retreiving the index
    get :index
    assert_response :success
  end

  test "should create sop with url" do
    assert_difference('Sop.count') do
      assert_difference('ContentBlob.count') do
        post :create, :sop => valid_sop_with_url, :sharing=>valid_sharing
      end
    end
    assert_redirected_to sop_path(assigns(:sop))
    assert_equal users(:quentin), assigns(:sop).contributor
    assert !assigns(:sop).content_blob.url.blank?
    assert assigns(:sop).content_blob.data_io_object.nil?
    assert !assigns(:sop).content_blob.file_exists?
    assert_equal "sysmo-db-logo-grad2.png", assigns(:sop).original_filename
    assert_equal "image/png", assigns(:sop).content_type
  end

  test "should create sop and store with url and store flag" do
    sop_details             =valid_sop_with_url
    sop_details[:local_copy]="1"
    assert_difference('Sop.count') do
      assert_difference('ContentBlob.count') do
        post :create, :sop => sop_details, :sharing=>valid_sharing
      end
    end
    assert_redirected_to sop_path(assigns(:sop))
    assert_equal users(:quentin), assigns(:sop).contributor
    assert !assigns(:sop).content_blob.url.blank?
    assert !assigns(:sop).content_blob.data_io_object.read.nil?
    assert assigns(:sop).content_blob.file_exists?
    assert_equal "sysmo-db-logo-grad2.png", assigns(:sop).original_filename
    assert_equal "image/png", assigns(:sop).content_type
  end

  test "should show sop" do
    login_as(:owner_of_my_first_sop)
    s=sops(:my_first_sop)
    get :show, :id => s.id
    assert_response :success
  end

  test "should get edit" do
    login_as(:owner_of_my_first_sop)
    get :edit, :id => sops(:my_first_sop)
    assert_response :success
    assert_select "h1", :text=>/Editing SOP/

    #this is to check the SOP is all upper case in the sharing form
    assert_select "label",:text=>/Keep this SOP private/
  end

  

  test "publications excluded in form for sops" do
    login_as(:owner_of_my_first_sop)
    get :edit, :id => sops(:my_first_sop)
    assert_response :success
    assert_select "div#publications_fold_content", false

    get :new
    assert_response :success
    assert_select "div#publications_fold_content", false
  end

  test "should update sop" do
    login_as(:owner_of_my_first_sop)
    put :update, :id => sops(:my_first_sop).id, :sop => {:title=>"Test2"}, :sharing=>valid_sharing
    assert_redirected_to sop_path(assigns(:sop))
  end


  test "should destroy sop" do
    login_as(:owner_of_my_first_sop)
    assert_difference('Sop.count', -1) do
      assert_no_difference("ContentBlob.count") do
        delete :destroy, :id => sops(:my_first_sop)
      end

    end
    assert_redirected_to sops_path
  end


  test "should not be able to edit exp conditions for downloadable only sop" do
    s=sops(:downloadable_sop)

    get :show, :id=>s
    assert_select "a", :text=>/Edit experimental conditions/, :count=>0
  end

  def test_should_be_able_to_edit_exp_conditions_for_owners_downloadable_only_sop
    login_as(:owner_of_my_first_sop)
    s=sops(:downloadable_sop)

    get :show, :id=>s
    assert_select "a", :text=>/Edit experimental conditions/, :count=>1
  end

  def test_should_be_able_to_edit_exp_conditions_for_editable_sop
    s=sops(:editable_sop)

    get :show, :id=>sops(:editable_sop)
    assert_select "a", :text=>/Edit experimental conditions/, :count=>1
  end

  def test_should_show_version
    s              =sops(:editable_sop)
    old_desc       =s.description
    old_desc_regexp=Regexp.new(old_desc)

    #create new version
    s.description  ="This is now version 2"
    assert s.save_as_new_version
    s=Sop.find(s.id)
    assert_equal 2, s.versions.size
    assert_equal 2, s.version
    assert_equal 1, s.versions[0].version
    assert_equal 2, s.versions[1].version

    get :show, :id=>sops(:editable_sop)
    assert_select "p", :text=>/This is now version 2/, :count=>1
    assert_select "p", :text=>old_desc_regexp, :count=>0

    get :show, :id=>sops(:editable_sop), :version=>"2"
    assert_select "p", :text=>/This is now version 2/, :count=>1
    assert_select "p", :text=>old_desc_regexp, :count=>0

    get :show, :id=>sops(:editable_sop), :version=>"1"
    assert_select "p", :text=>/This is now version 2/, :count=>0
    assert_select "p", :text=>old_desc_regexp, :count=>1

  end

  def test_should_create_new_version
    s=sops(:editable_sop)

    assert_difference("Sop::Version.count", 1) do
      post :new_version, :id=>s, :sop=>{:data=>fixture_file_upload('files/file_picture.png')}, :revision_comment=>"This is a new revision"
    end

    assert_redirected_to sop_path(s)
    assert assigns(:sop)
    assert_not_nil flash[:notice]
    assert_nil flash[:error]

    s=Sop.find(s.id)
    assert_equal 2, s.versions.size
    assert_equal 2, s.version
    assert_equal "file_picture.png", s.original_filename
    assert_equal "file_picture.png", s.versions[1].original_filename
    assert_equal "little_file.txt", s.versions[0].original_filename
    assert_equal "This is a new revision", s.versions[1].revision_comments

  end

  def test_should_not_create_new_version_for_downloadable_only_sop
    s                    =sops(:downloadable_sop)
    current_version      =s.version
    current_version_count=s.versions.size

    assert_no_difference("Sop::Version.count") do
      post :new_version, :id=>s, :data=>fixture_file_upload('files/file_picture.png'), :revision_comment=>"This is a new revision"
    end

    assert_redirected_to sop_path(s)
    assert_not_nil flash[:error]

    s=Sop.find(s.id)
    assert_equal current_version_count, s.versions.size
    assert_equal current_version, s.version

  end

  def test_should_duplicate_conditions_for_new_version
    s=sops(:editable_sop)
    condition1 = ExperimentalCondition.create(:unit        => units(:gram), :measured_item => measured_items(:weight),
                                              :start_value => 1, :sop_id => s.id, :sop_version => s.version)
    assert_difference("Sop::Version.count", 1) do
      post :new_version, :id=>s, :sop=>{:data=>fixture_file_upload('files/file_picture.png')}, :revision_comment=>"This is a new revision" #v2
    end

    assert_not_equal 0, s.find_version(1).experimental_conditions.count
    assert_not_equal 0, s.find_version(2).experimental_conditions.count
    assert_not_equal s.find_version(1).experimental_conditions, s.find_version(2).experimental_conditions
  end

  def test_adding_new_conditions_to_different_versions
    s =sops(:editable_sop)
    condition1 = ExperimentalCondition.create(:unit => units(:gram), :measured_item => measured_items(:weight),
                                              :start_value => 1, :sop_id => s.id, :sop_version => s.version)
    assert_difference("Sop::Version.count", 1) do
      post :new_version, :id=>s, :sop=>{:data=>fixture_file_upload('files/file_picture.png')}, :revision_comment=>"This is a new revision" #v2
    end

    s.find_version(2).experimental_conditions.each { |e| e.destroy }
    assert_equal condition1, s.find_version(1).experimental_conditions.first
    assert_equal 0, s.find_version(2).experimental_conditions.count

    condition2 = ExperimentalCondition.create(:unit => units(:gram), :measured_item => measured_items(:weight),
                                              :start_value => 2, :sop_id => s.id, :sop_version => 2)

    assert_not_equal 0, s.find_version(2).experimental_conditions.count
    assert_equal condition2, s.find_version(2).experimental_conditions.first
    assert_not_equal condition2, s.find_version(1).experimental_conditions.first
    assert_equal condition1, s.find_version(1).experimental_conditions.first
  end

  def test_should_add_nofollow_to_links_in_show_page
    get :show, :id=> sops(:sop_with_links_in_description)
    assert_select "div#description" do
      assert_select "a[rel=nofollow]"
    end
  end

  def test_can_display_sop_with_no_contributor
    get :show, :id=>sops(:sop_with_no_contributor)
    assert_response :success
  end

  def test_can_show_edit_for_sop_with_no_contributor
    get :edit, :id=>sops(:sop_with_no_contributor)
    assert_response :success
  end

  def test_editing_doesnt_change_contributor
    login_as(:pal_user) #this user is a member of sysmo, and can edit this sop
    sop=sops(:sop_with_no_contributor)
    put :update, :id => sop, :sop => {:title=>"blah blah blah"}, :sharing=>valid_sharing
    updated_sop=assigns(:sop)
    assert_redirected_to sop_path(updated_sop)
    assert_equal "blah blah blah", updated_sop.title, "Title should have been updated"
    assert_nil updated_sop.contributor, "contributor should still be nil"
  end

  test "filtering by assay" do
    assay=assays(:metabolomics_assay)
    get :index, :filter => {:assay => assay.id}
    assert_response :success
  end

  test "filtering by study" do
    study=studies(:metabolomics_study)
    get :index, :filter => {:study => study.id}
    assert_response :success
  end

  test "filtering by investigation" do
    inv=investigations(:metabolomics_investigation)
    get :index, :filter => {:investigation => inv.id}
    assert_response :success
  end

  test "filtering by project" do
    project=projects(:sysmo_project)
    get :index, :filter => {:project => project.id}
    assert_response :success
  end

  test "filtering by person" do
    login_as(:owner_of_my_first_sop)
    person = people(:person_for_owner_of_my_first_sop)
    p      =projects(:sysmo_project)
    get :index, :filter=>{:person=>person.id}, :page=>"all"
    assert_response :success
    sop  = sops(:downloadable_sop)
    sop2 = sops(:sop_with_fully_public_policy)
    assert_select "div.list_items_container" do
      assert_select "a", :text=>sop.title, :count=>1
      assert_select "a", :text=>sop2.title, :count=>0
    end
  end

  test "should not be able to update sharing without manage rights" do
    login_as(:quentin)
    user = users(:quentin)
    sop   = sops(:sop_with_all_sysmo_users_policy)

    assert sop.can_edit?(user), "sop should be editable but not manageable for this test"
    assert !sop.can_manage?(user), "sop should be editable but not manageable for this test"
    assert_equal Policy::EDITING, sop.policy.access_type, "data file should have an initial policy with access type for editing"
    put :update, :id => sop, :sop => {:title=>"new title"}, :sharing=>{:use_whitelist=>"0", :user_blacklist=>"0", :sharing_scope =>Policy::ALL_SYSMO_USERS, "access_type_#{Policy::ALL_SYSMO_USERS}"=>Policy::NO_ACCESS}
    assert_redirected_to sop_path(sop)
    sop.reload

    assert_equal "new title", sop.title
    assert_equal Policy::EDITING, sop.policy.access_type, "policy should not have been updated"

  end

  test "owner should be able to update sharing" do
    login_as(:owner_of_editing_for_all_sysmo_users_policy)
    user = users(:owner_of_editing_for_all_sysmo_users_policy)
    sop   = sops(:sop_with_all_sysmo_users_policy)

    assert sop.can_edit?(user), "sop should be editable and manageable for this test"
    assert sop.can_manage?(user), "sop should be editable and manageable for this test"
    assert_equal Policy::EDITING, sop.policy.access_type, "data file should have an initial policy with access type for editing"
    put :update, :id => sop, :sop => {:title=>"new title"}, :sharing=>{:use_whitelist=>"0", :user_blacklist=>"0", :sharing_scope =>Policy::ALL_SYSMO_USERS, "access_type_#{Policy::ALL_SYSMO_USERS}"=>Policy::NO_ACCESS}
    assert_redirected_to sop_path(sop)
    sop.reload

    assert_equal "new title", sop.title
    assert_equal Policy::NO_ACCESS, sop.policy.access_type, "policy should have been updated"
  end

  test "update with ajax only applied when viewable" do
    login_as(:aaron)
    user=users(:aaron)
    sop=sops(:sop_with_fully_public_policy)
    assert sop.tag_counts.empty?,"This should have no tags for this test to work"
    golf_tags=tags(:golf)
    
    assert_difference("ActsAsTaggableOn::Tagging.count") do
      xml_http_request :post, :update_tags_ajax,{:id=>sop.id,:tag_autocompleter_unrecognized_items=>[],:tag_autocompleter_selected_ids=>[golf_tags.id]}
    end

    sop.reload

    assert_equal ["golf"],sop.tag_counts.collect(&:name)

    sop=sops(:private_sop)
    assert sop.tag_counts.empty?,"This should have no tags for this test to work"
    
    assert !sop.can_view?(user),"Aaron should not be able to view this item for this test to be valid"

    assert_no_difference("ActsAsTaggableOn::Tagging.count") do
      xml_http_request :post, :update_tags_ajax,{:id=>sop.id,:tag_autocompleter_unrecognized_items=>[],:tag_autocompleter_selected_ids=>[golf_tags.id]}
    end

    sop.reload

    assert sop.tag_counts.empty?,"This should still have no tags"

  end

  test "update tags with ajax" do
    p = Factory :person

    login_as p.user

    p2 = Factory :person
    sop = Factory :sop,:contributor=>p.user


    assert sop.annotations.empty?,"this sop should have no tags for the test"

    golf = Factory :tag,:annotatable=>sop,:source=>p2.user,:value=>"golf"
    Factory :tag,:annotatable=>sop,:source=>p2.user,:value=>"sparrow"

    sop.reload

    assert_equal ["golf","sparrow"],sop.annotations.collect{|a| a.value.text}.sort
    assert_equal [],sop.annotations.select{|a| a.source==p.user}.collect{|a| a.value.text}.sort
    assert_equal ["golf","sparrow"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort

    xml_http_request :post, :update_annotations_ajax,{:id=>sop,:tag_autocompleter_unrecognized_items=>["soup"],:tag_autocompleter_selected_ids=>[golf.id]}

    sop.reload

    assert_equal ["golf","soup","sparrow"],sop.annotations.collect{|a| a.value.text}.uniq.sort
    assert_equal ["golf","soup"],sop.annotations.select{|a| a.source==p.user}.collect{|a| a.value.text}.sort
    assert_equal ["golf","sparrow"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort

  end

  test "should update sop tags" do
    p = Factory :person
    sop=Factory :sop,:contributor=>p
    dummy_sop = Factory :sop

    login_as p.user
    assert sop.annotations.empty?,"Should have no annotations"
    Factory :tag,:source=>p.user,:annotatable=>sop,:value=>"fish"
    Factory :tag,:source=>p.user,:annotatable=>sop,:value=>"apple"
    golf = Factory :tag, :source=>p.user, :annotatable=>dummy_sop, :value=>"golf"

    sop.reload
    assert_equal ["apple","fish"],sop.annotations.collect{|a| a.value.text}.sort

    put :update, :id => sop, :tag_autocompleter_unrecognized_items=>["soup"],:tag_autocompleter_selected_ids=>[golf.id],:sop=>{}, :sharing=>valid_sharing
    sop.reload

    assert_equal ["golf","soup"],sop.annotations.collect{|a| a.value.text}.sort
  end

  test "should update sop tags with correct ownership" do
    p1=Factory :person
    p2=Factory :person
    p3=Factory :person

    sop = Factory :sop,:contributor=>p1

    assert sop.annotations.empty?, "This sop should have no tags"

    login_as p1.user

    Factory :tag,:source=>p1.user,:annotatable=>sop,:value=>"fish"
    Factory :tag,:source=>p2.user,:annotatable=>sop,:value=>"fish"
    golf = Factory :tag,:source=>p2.user,:annotatable=>sop,:value=>"golf"
    Factory :tag,:source=>p3.user,:annotatable=>sop,:value=>"apple"

    sop.reload

    assert_equal ["fish"],sop.annotations.select{|a|a.source==p1.user}.collect{|a| a.value.text}
    assert_equal ["fish","golf"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort
    assert_equal ["apple"],sop.annotations.select{|a|a.source==p3.user}.collect{|a| a.value.text}
    assert_equal ["apple","fish","golf"],sop.annotations.collect{|a| a.value.text}.uniq.sort

    put :update, :id => sop, :tag_autocompleter_unrecognized_items=>["soup"],:tag_autocompleter_selected_ids=>[golf.id],:sop=>{}, :sharing=>valid_sharing
    sop.reload

    assert_equal ["soup"],sop.annotations.select{|a|a.source==p1.user}.collect{|a| a.value.text}
    assert_equal ["golf"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort
    assert_equal [],sop.annotations.select{|a|a.source==p3.user}.collect{|a| a.value.text}
    assert_equal ["golf","soup"],sop.annotations.collect{|a| a.value.text}.uniq.sort

  end

  test "should update sop tags with correct ownership2" do
    #a specific case where a tag to keep was added by both the owner and another user.
    #Test checks that the correct tag ownership is preserved.

    p1=Factory :person
    p2=Factory :person

    sop = Factory :sop,:contributor=>p1

    assert sop.annotations.empty?, "This sop should have no tags"

    login_as p1.user

    Factory :tag,:source=>p1.user,:annotatable=>sop,:value=>"fish"
    golf = Factory :tag,:source=>p1.user,:annotatable=>sop,:value=>"golf"
    Factory :tag,:source=>p2.user,:annotatable=>sop,:value=>"apple"
    Factory :tag,:source=>p2.user,:annotatable=>sop,:value=>"golf"

    sop.reload

    assert_equal ["fish","golf"],sop.annotations.select{|a|a.source==p1.user}.collect{|a| a.value.text}.sort
    assert_equal ["apple","golf"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort

    put :update, :id => sop, :tag_autocompleter_unrecognized_items=>[],:tag_autocompleter_selected_ids=>[golf.id],:sop=>{}, :sharing=>valid_sharing
    sop.reload

    assert_equal ["golf"],sop.annotations.select{|a|a.source==p1.user}.collect{|a| a.value.text}.sort
    assert_equal ["golf"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort

  end

  test "update tags with known tags passed as unrecognised" do
    #checks that when a known tag is incorrectly passed as a new tag, it is correctly handled
    #this can happen when a tag is typed in full, rather than relying on autocomplete, and can affect the correct preservation of ownership

    p1=Factory :person
    p2=Factory :person

    sop = Factory :sop,:contributor=>p1

    assert sop.annotations.empty?, "This sop should have no tags"

    login_as p1.user

    fish = Factory :tag,:source=>p1.user,:annotatable=>sop,:value=>"fish"
    golf = Factory :tag,:source=>p1.user,:annotatable=>sop,:value=>"golf"
    Factory :tag,:source=>p2.user,:annotatable=>sop,:value=>"fish"
    Factory :tag,:source=>p2.user,:annotatable=>sop,:value=>"soup"

    sop.reload

    assert_equal ["fish","golf"],sop.annotations.select{|a|a.source==p1.user}.collect{|a| a.value.text}.sort
    assert_equal ["fish","soup"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort

    put :update, :id => sop, :tag_autocompleter_unrecognized_items=>["fish"],:tag_autocompleter_selected_ids=>[golf.id],:sop=>{}, :sharing=>valid_sharing

    sop.reload

    assert_equal ["fish","golf"],sop.annotations.select{|a|a.source==p1.user}.collect{|a| a.value.text}.sort
    assert_equal ["fish"],sop.annotations.select{|a|a.source==p2.user}.collect{|a| a.value.text}.sort

  end

  test "do publish" do
    login_as(:owner_of_my_first_sop)
    sop=sops(:my_first_sop)
    assert sop.can_manage?,"The sop must be manageable for this test to succeed"
    post :publish,:id=>sop
    assert_response :success
    assert_nil flash[:error]
    assert_not_nil flash[:notice]
  end

  test "do not publish if not can_manage?" do
    sop=sops(:my_first_sop)
    assert !sop.can_manage?,"The sop must not be manageable for this test to succeed"
    post :publish,:id=>sop
    assert_redirected_to sop
    assert_not_nil flash[:error]
    assert_nil flash[:notice]
  end

  test "get preview_publish" do
    login_as(:owner_of_my_first_sop)
    sop=sops(:my_first_sop)
    assert sop.can_manage?,"The sop must be manageable for this test to succeed"
    get :preview_publish, :id=>sop
    assert_response :success
  end

  test "cannot get preview_publish when not manageable" do
    sop=sops(:my_first_sop)
    assert !sop.can_manage?,"The sop must not be manageable for this test to succeed"
    get :preview_publish, :id=>sop
    assert_redirected_to sop
    assert flash[:error]
  end

  private

  def valid_sop_with_url
    {:title=>"Test", :data_url=>"http://www.sysmo-db.org/images/sysmo-db-logo-grad2.png",:projects=>[projects(:sysmo_project)]}
  end

  def valid_sop
    {:title=>"Test", :data=>fixture_file_upload('files/file_picture.png'),:projects=>[projects(:sysmo_project)]}
  end

end
