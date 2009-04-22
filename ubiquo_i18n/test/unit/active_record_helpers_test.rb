require File.dirname(__FILE__) + "/../test_helper.rb"

class Ubiquo::ActiveRecordHelpersTest < ActiveSupport::TestCase

  
  def test_simple_filter
    create_model(:content_id => 1, :locale => 'es')
    create_model(:content_id => 1, :locale => 'ca')
    assert_equal 1, TestModel.locale('es').size
    assert_equal 'es', TestModel.locale('es').first.locale
  end
  
  def test_many_contents
    create_model(:content_id => 1, :locale => 'es')
    create_model(:content_id => 2, :locale => 'es')
    assert_equal 2, TestModel.locale('es').size
    assert_equal %w{es es}, TestModel.locale('es').map(&:locale)
  end
  
  def test_many_locales_many_contents
    create_model(:content_id => 1, :locale => 'es')
    create_model(:content_id => 1, :locale => 'ca')
    create_model(:content_id => 2, :locale => 'es')
    
    assert_equal 2, TestModel.locale('es').size
    assert_equal 1, TestModel.locale('ca').size
    assert_equal 2, TestModel.locale('ca', 'es').size
    assert_equal %w{ca es}, TestModel.locale('ca', 'es').map(&:locale)
  end
  
  def test_search_all_locales_sorted
    create_model(:content_id => 1, :locale => 'es')
    create_model(:content_id => 1, :locale => 'ca')
    create_model(:content_id => 2, :locale => 'es')
    create_model(:content_id => 2, :locale => 'en')
    
    assert_equal %w{ca es}, TestModel.locale('ca', :ALL).map(&:locale)
    assert_equal %w{es en}, TestModel.locale('en', :ALL).map(&:locale)
    assert_equal %w{es es}, TestModel.locale('es', :ALL).map(&:locale)
    assert_equal %w{ca en}, TestModel.locale('ca', 'en', :ALL).map(&:locale)
    
    # :ALL position is indifferent
    assert_equal %w{es en}, TestModel.locale(:ALL, 'en').map(&:locale)
  end
  
  def test_search_by_content
    create_model(:content_id => 1, :locale => 'es')
    create_model(:content_id => 1, :locale => 'ca')
    create_model(:content_id => 2, :locale => 'es')
    create_model(:content_id => 2, :locale => 'en')
    
    assert_equal %w{es ca}, TestModel.content(1).map(&:locale)
    assert_equal %w{es ca es en}, TestModel.content(1, 2).map(&:locale)
  end
  
  def test_search_by_content_and_locale
    create_model(:content_id => 1, :locale => 'es')
    create_model(:content_id => 1, :locale => 'ca')
    create_model(:content_id => 2, :locale => 'es')
    create_model(:content_id => 2, :locale => 'en')
    
    assert_equal %w{es}, TestModel.locale('es').content(1).map(&:locale)
    assert_equal %w{ca en}, TestModel.content(1, 2).locale('ca', 'en').map(&:locale)
    assert_equal %w{ca es}, TestModel.content(1, 2).locale('ca', 'es').map(&:locale)
    assert_equal %w{}, TestModel.content(1).locale('en').map(&:locale)
  end
  
  def test_search_translations
    es_m1 = create_model(:content_id => 1, :locale => 'es')
    ca_m1 = create_model(:content_id => 1, :locale => 'ca')
    de_m1 = create_model(:content_id => 1, :locale => 'de')
    es_m2 = create_model(:content_id => 2, :locale => 'es')
    en_m2 = create_model(:content_id => 2, :locale => 'en')
    en_m3 = create_model(:content_id => 3, :locale => 'en')
    
    assert_equal_set [es_m1, de_m1], ca_m1.translations
    assert_equal_set [ca_m1, de_m1], es_m1.translations
    assert_equal_set [en_m2], es_m2.translations
    assert_equal [], en_m3.translations
  end
  
  def test_translations_uses_named_scope
    # this is what is tested
    TestModel.expects(:translations)
    # since we mock translations, the following needs to be mocked too (called on creation)
    TestModel.any_instance.expects(:update_translations)
    create_model(:content_id => 1, :locale => 'es').translations
  end
      
end

create_test_model_backend
