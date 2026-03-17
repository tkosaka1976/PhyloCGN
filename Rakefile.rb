require 'rake/clean'
require_relative 'rakelib/config.rb'
require_relative 'rakelib/modules.rb'

import 'rakelib/prepare_tree.rake'
import 'rakelib/neighborhood.rake'
import 'rakelib/analyze_pcgn.rake'
import 'rakelib/utility.rake'