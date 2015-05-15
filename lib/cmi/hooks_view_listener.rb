class Cmi::HooksViewListener < Redmine::Hook::ViewListener
  render_on :view_layouts_base_sidebar, :partial => "metrics/cmi_metrics_sidebar"
end
