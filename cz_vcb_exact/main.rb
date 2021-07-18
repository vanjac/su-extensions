require 'sketchup.rb'
require 'win32ole'
require 'base64'
require 'tempfile'
require 'shellwords'


module Chroma
  PLUGIN_PATH = "Plugins/cz_vcb_exact"

  def self.enter_exact_vcb
    # https://stackoverflow.com/a/47639662
    script = READ_VCB_SCRIPT + Shellwords.escape(@@vcb_temp_file.path)
    encoded = Base64.strict_encode64(script.encode('utf-16le'))
    command = "powershell.exe -encodedCommand #{encoded}"
    # run command WITHOUT showing window
    # https://www.ruby-forum.com/t/hiding-the-command-window-when-using-system-on-windows/75495/4
    result = @@wsh.Run(command, 0, 1)
    if result != 0
      if result == 1
        UI.messagebox("Couldn't find SketchUp window (not focused)")
      elsif result == 2
        UI.messagebox("Couldn't find Measurements toolbar")
      else
        UI.messagebox("Error reading measurement")
      end
      return
    end
    @@vcb_temp_file.open
    begin
      vcb_value = @@vcb_temp_file.read
    ensure
      @@vcb_temp_file.close
    end
    puts "VCB: " + vcb_value
    if vcb_value.include? "~"
      UI.messagebox("VCB isn't exact! (indicated by ~)")
      return
    end
    @@wsh.SendKeys(vcb_value + "~")
  end

  unless file_loaded?(__FILE__)
    @@wsh = WIN32OLE.new('Wscript.Shell')
    # should be deleted when sketchup is closed
    @@vcb_temp_file = Tempfile.new('cz_vcb')
    @@vcb_temp_file.close

    UI.menu.add_item('Enter Exact Measurement') {
      enter_exact_vcb
    }
  end

  # the following is PowerShell code
  READ_VCB_SCRIPT = %q{
    using namespace System.Windows.Automation
    Add-Type -AssemblyName UIAutomationClient
    # TODO also UIAutomationTypes?

    $focused = [AutomationElement]::FocusedElement
    # search up until we find the window
    # https://www.meziantou.net/detect-the-opening-of-a-new-window-in-csharp.htm
    while ($focused.Current.ControlType -ne [ControlType]::Window) {
      $focused = [TreeWalker]::RawViewWalker.GetParent($focused)
      if ($null -eq $focused) {
        exit 1  # bad focus
      }
    }
    $findVCBEdit = New-Object PropertyCondition ([AutomationElement]::AutomationIdProperty), "24214"
    $vcbEdit = $focused.FindFirst("Descendants", $findVCBEdit)
    if ($null -eq $vcbEdit) {
      exit 2  # can't find measurements toolbar
    }
    $vcbValue = $vcbEdit.Current.Name
    Set-Content -Value $vcbValue -Path }  # file name goes here!
end