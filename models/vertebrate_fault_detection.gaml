/**
* Name: Decentralized Model with Leader among Groups
* Tags: 
*/


model CoopModel

global {
	
	float world_size <- 250#m;
	geometry shape <- envelope(square(world_size));
	
	string setup_file<-""; 	//path to the file for the shop floor setup up
	bool check_abort <- true; //activate check for condition to end simulation
		
	int transporter_no <- 10;
	float init_prob <- 0.05 min: 0.0 max: 1.0;
	float new_tie_prob <- 0.05; //Cantor: 0.0001;
	
	list<list<transporter>> groups <- []; //all cooperational groups of agents including singleton groups
	list<list<transporter>> non_solo_groups <- []; //all cooperational groups of agents with more than one member;
	list<float> groups_share <- []; //holds the respective share pre group (adressed by index, s.t. groups[i] <--> groups_share[i] belong together)  
	
	int R <- 0; //given goal state for cooperation (Cantor: total share of group resource) 

	float init_com_radius <- 0.0#m;	
	
	bool verbose_mode <- false;
	
	init{ 
		
		write "Init: R = " + R;
		
		file my_file <- text_file(setup_file); //get setup of agents                 
        
          loop el over: my_file {
        	//entries have shape agent, x,y, size
        	list tmp <- el split_with ',';        

			if(length(tmp) < 4)
			{
				error "not enough entries at " + tmp[0] + " (missing coordinates or size?)";
			} 

			int x <- int(tmp[1]);
			int y <- int(tmp[2]);
			
			if(x >= shape.width or y >= shape.height or x < 0 or y < 0)
			{
				error "Coordinates for out of bounds (width = " + shape.width + ")!";
			} 
        	
    		create transporter {
  				location <- {x,y};
  				size <- int(tmp[3]); //read size from file 
			}
        	
        }
        
		//create transporter number: transporter_no;
		transporter_no <- length(transporter);
		
		ask transporter{
		
			com_radius <- init_com_radius;
		
			//loop t over: (transporter-self){
			loop t over: (transporters_in_reach()){
			
				
				if(flip(init_prob)){
					add t to: self.ties;
				}
			}
		}
		
		if(verbose_mode){
			write "R = " + R ;
			ask transporter {
				write self.name + "  " + self.ties;
			}
		}
	}
	//##################
	
	reflex calculate_ties_and_groups {
		
		list<pair<transporter, transporter>> sym <- find_symm();
	   
	    ask transporter {
	    	visited <- 0; //reset all transporters
	    	i_am_alone <- true; //reset group
	    }
	    
		groups <- []; //reset groups	    
		non_solo_groups <-[];
		groups_share <- [];
	    loop t over: transporter{
	    	if(t.visited = 0){
	    		list<transporter> gr <- []; //create new list
	    		do DFSGroup(t, sym, gr);
	    		add gr to: groups;
	    	}
	    }
		
	    if(verbose_mode){
		    //write groups;
		    write "####################################################";
		    write "Groups:";
	    }
	    
	    if(length(groups) > 0)
	    {
	    	loop i from: 0 to: length(groups)-1{
	    	if(verbose_mode){
	    		write "Group " + i + ", size " + length(groups[i]);
	    	}
	    	
	    	if(length(groups[i]) > 1)
	    	{
	    		ask groups[i]{
	    			self.i_am_alone <- false; //transporter is part of group
	    		}
	    	}
	    	
	    	}
	    }else
	    {
	    	if(verbose_mode){
	    		write "no groups";
	    	}
	    }
	    
	    
	}

	//Adapted for different performance of agents
	reflex social_foraging {
		
		non_solo_groups <- groups where (length(each) > 1); 
		
		if(length(non_solo_groups) > 0)
		{
			//agents do not calculate a share to decide on, but rather take the observation of the performance. 
			//Here, we calculate in the global reflex (centralized) to avoid that agents get into a race condition while evaluating the group's performance.  
			
			loop i from: 0 to: length(non_solo_groups)-1 {
				
				//share manipulated by actual size
				float share <-  R / (non_solo_groups[i] sum_of(each.size)) ;//per capita share
				
				groups_share <- groups_share + share;//save share per group
				
				if(verbose_mode){
					write "Group " + i + " has per cap: " + share ;
				}
				
				if(share = 1){
					
					ask non_solo_groups[i]{
						
						fault_counter <- 0; // reset fault counter directly to zero
						do decrease_com_radius(); // decerase com radius by one step
					}
					
				} else if(share > 1){
					//missed opportunities
					
					ask non_solo_groups[i]{
						
						do increase_com_radius(); 
							
						//any transporter in reach that is not already tied to me - could also be already tied transporter
						transporter t <- one_of(self.transporters_in_reach()); 
						
						//tend to take transporters in reach that have smaller asshat counter than anyone else 
						list<transporter> in_reach <- self.transporters_in_reach();
						 
						transporter zeros <- one_of(in_reach where (each.fault_counter = 0));
						
						if(zeros != nil){
							t <- zeros;
						}else{
							list<float> prob <- [];
							int sum_fault <- in_reach sum_of (each.fault_counter);
							loop l over: in_reach{
								prob <- prob + (l.fault_counter/ sum_fault);
							}
												
							transporter non_zeroes <- first(sample(in_reach, 1,false, prob));
							
							t <- non_zeroes;
						}
						 
						if(t != nil){
							add t to: self.ties;
						}
						
						ties <- remove_duplicates(ties);
						
					}
					
				}else if(share < 1) {
					//negative outcome
					
					//every member of the group:
					ask non_solo_groups[i]{
						
						transporter t <- one_of(self.ties); //take one of ALL present ties 
						
						remove t from: self.ties;
						//remove a random tie, increase that one's fault counter
						if(t != nil){
							t.fault_counter <- t.fault_counter +1;
						}
					}
				}
			}
			
			if(verbose_mode){
				loop i from: 0 to: length(non_solo_groups)-1 {
					write "Group " + string(i) + " has " + length(non_solo_groups[i]) + " members: " + non_solo_groups[i];
				}	
			}
		}
	}

	/*create a random new relation each cycle w.r.t. probability*/
	reflex random_new_ties {
		
		ask transporter {
			if(flip(new_tie_prob)){
				/*create new random tie */
				list<transporter> available_new_ties <- self.transporters_in_reach()-self.ties;
				
				if((!(available_new_ties contains nil)) and (! empty(available_new_ties))){
					add one_of(available_new_ties) to: self.ties;
					
					if(verbose_mode){
						write "created new tie for " + self.name color:#red;
					}
				}
			}
		}
	}
	
	//end conditions for algorithm -- if R groups are found and they have ideal usage, the algorithm is done
	reflex check_for_end_sim when:check_abort{
		
		if((length(transporter) mod R) != 0){
			//if the number of expected groups is found
			if(length(non_solo_groups where (length(each) = R)) = int(length(transporter) / R)  ){
				
				//if all these groups have a share of 1.0 (which means ideal usage)
				if(groups_share all_match (each = 1.0)){
					//end simulation as all groups have been found and their usage is ideal
					do endOfAlgorithm;
				}	
			}
			
		}else{
				//we allow for one less, as the epectation is that we will have one "splittered" or at least not full group
				if(length(non_solo_groups where (length(each) = R)) = (int(length(transporter) / R) -1)  ){
				
					bool checked_all <- true;
				
					loop i from: 0 to:(length(non_solo_groups)-1){
						if(length(non_solo_groups[i]) = R ){
							if(groups_share[i] = 1.0){
								//all good check next
								//this tedious loop is to ensure that we only check groups that actually have R members 
						}else{
							//right amount of agents but not ideal usage
							checked_all <- false;					
							break;
						}
					}
				}
				
				//if all these groups have a share of 1.0 (which means ideal usage)
				if(checked_all){
					//end simulation as all groups have been found and their usage is ideal				
					do endOfAlgorithm;
				}
			}
		}
	}
	

	/************************************************Actions************************************************/
	
	/*Find symmetric relations between agents*/
	list<pair<transporter, transporter>> find_symm{
		
		list<pair<transporter, transporter>> sym <- []; //symmetrical relations
		
		ask transporter {
			
			loop t over: (self.ties){
				
				if(t.ties contains self){
					
					if(! (sym contains (t::self))){
						add self::t to: sym;	
					}
				}
			}
			
		}
		return sym;
	}

	/*Depth first search for Groups. Takes to be checked transporter, list of symmetric relations and currently built group */
	action DFSGroup(transporter t, list<pair<transporter, transporter>> sym, list<transporter> group){
		t.visited <- 1; //mark transporter as visited
		//write t.name;
		add t to: group;
		
		loop s over: sym{
			if(s.key = t){
				if(s.value.visited = 0){ //not visited
					do DFSGroup2(s.value, sym,group);
				}
			}else if(s.value = t){
				if(s.key.visited = 0){ //not visited
					do DFSGroup2(s.key, sym,group);
				}
			}
		}
	}

	/* for recursive call*/
	action DFSGroup2(transporter t, list<pair<transporter, transporter>> sym,list<transporter> group){
		do DFSGroup(t,sym,group);
	}
	
	/* Takes all transporters that are not in ideal groups, sorts them and prints their information*/
	action endOfAlgorithm{
		write "End of algorithm - groups were found" color:#red;
						
		list<transporter> singletons <- [];
		
		list<list<transporter>> non_full <- (groups where (length(each) != R) );
		
		loop g over: non_full {
			loop t over:g {
				singletons <- singletons + t; //add all agents to list
			}
		}

		singletons <- singletons sort_by each.fault_counter;
		
		loop s over: singletons
		{
			write s.name + " - " + s.fault_counter + " " + (s.size > 1.0 ? "(faulty)" :  "");
		}
		
		check_abort <- false;
	}
}

//schedules agents, such that the simulation of their behaviour and the reflex evaluation is random and not always in the same order 
species scheduler schedules: shuffle(transporter);

species transporter schedules:[] {
	
	list<transporter> ties <- [];
	bool i_am_alone <- true;
	
	int fault_counter <- 0 min:0;
	
	int size <- 1; //amount of ressources a transporter needs
	int visited <- 0;//for searching and marking groups

	float com_radius <- 25.0 min: 0.0 max: (float(world_size)* 1.5); //com range is limited to >sqrt(2)*world_size which means two agents on opposite corners of the environment can still reach each other, IFF they want to 
	
	reflex when: i_am_alone {
		
		//increase com radius as transporter naturally wants to increase chance to find mates
		//small prob lets agent first search local area before extending radius; 1.0 leads to extension in every step
		
		 do increase_com_radius();

		//for any transporter in reach that is not already tied to me - could also be already tied transporter
		transporter t <- one_of(self.transporters_in_reach()); 
		if(t != nil){
			add t to: self.ties;
			ties <- remove_duplicates(ties);
		}
	}
	
	/*Returns all transporters in communication distance without self*/
	list<transporter> transporters_in_reach{
		
		list<transporter> t <- [];
		
		if(com_radius > 0){
			
			list<agent> A <- agents_inside(circle(com_radius)) ;

			if(A contains nil)
			{
				error "A contains NIL at " + name ;
			}
			
			list<transporter> all_near <- (agents_inside(circle(com_radius)) of_generic_species transporter);
			
			if((!empty(all_near) ) or (all_near = nil)){
				t <- (all_near-self);
			}
		}
		
		return t;
	}
	
	action increase_com_radius{
		com_radius <- com_radius + 0.1;
	}
		
	action decrease_com_radius{
		com_radius <- com_radius - 0.1;
	}
	
	aspect base{
		if(size > 1){
			draw circle(3.0) color: #orange border:#grey;
		}else{
			draw circle(2.0) color: #grey border:#grey;	
		}
		
		draw circle(com_radius) color: #transparent border:#lightgrey;	
	}
	
	aspect showName{
		draw string(name) color: #red ;
	}

	//draws arrow to show current target station 
	aspect ties{ 
		if(ties != nil)
    	{
    		loop t over:ties{
    			
    			if(t.ties contains self)
    			{
    				draw line([location,t.location]) color: #darkblue end_arrow: 1 ;
    			}
    		}
    	}  
	}

} 

/*####################################################*/

experiment DecFaultDetection type:gui{

	//parameter var: setup_file <- "../includes/diagonal.csv";
	//parameter var: setup_file <- "../includes/checker.csv";
	parameter var: setup_file <- "../includes/free.csv";
	//parameter var: setup_file <- "../includes/free105.csv";

	parameter var: world_size <- 250#m;
	parameter var:R<- 3;

	parameter var:new_tie_prob <- 0.0005; //Cantor: 0.0001;
	parameter var: init_prob <- 0.05 min: 0.0 max: 1.0;
	
	parameter var:init_com_radius <- 10.0#m ; //[0.0#m , 10.0#m, 25.0#m, 50#m ]; 
	
	output {	
		layout #split;
	 	display "Shop floor display" { 
			species transporter aspect: base;
			species transporter aspect: showName;
			species transporter aspect: ties;
			
		}
		
		inspect "my_species_inspector" value: transporter attributes: ["name","fault_counter"] type:table;
	}
}

/*Runs an amount of simulations in parallel, varies the initial communication radius*/
//"check_abort = false" equals length(groups where (length(each) = R)) = int(length(transporter) / R)) with all groups having share 1.0
experiment Performance type: batch until: ((check_abort = false) or (cycle > 50000) ) repeat: 100 autorun: true keep_seed: true{ 

	parameter var: setup_file <- "../includes/checker.csv"; //1
	//parameter var: setup_file <- "../includes/free.csv"; //2
	//parameter var: setup_file <- "../includes/diagonal.csv"; //3
	//parameter var: setup_file <- "../includes/free105.csv"; //4
		
	parameter var: world_size <- 250#m;
	parameter var:R <- 3;
	parameter var:new_tie_prob <- 0.0005; //Cantor: 0.0001
	parameter var: init_prob <- 0.05 min: 0.0 max: 1.0;
	
	parameter var:init_com_radius among: [0.0#m , 10.0#m, 25.0#m, 50#m ]; 
	parameter var: check_abort <- true;

	reflex save_results_explo {
    ask simulations {
			
			list<list<transporter>> singleton_groups <- (self.groups where (length(each) != R) ) ;
			
			list<transporter> singletons <- [];
			
			loop g over: singleton_groups{
				loop s over: g{ 
					add s to: singletons;
				}
			}
			
			singletons <- singletons sort_by each.fault_counter;
			
			loop s over: (singletons )
			{
				write s.name + " - " + s.fault_counter + " " + (s.size > 1.0 ? "(faulty)" :  "");
			}
			
			transporter highest_counter <- last((singletons sort_by (each.fault_counter)));
			transporter faulty_transporter <- first((self.transporter where (each.size > 1.0)));
			
			float average_com_range <- transporter mean_of (each.com_radius);
			
			float average_ties <- transporter mean_of (length(each.ties));
		
		//init_com_radius
    	save [int(self), self.cycle,  highest_counter, faulty_transporter, (faulty_transporter = highest_counter), average_com_range, init_com_radius, length(transporter),average_ties ]
           to: "/simulation_results/1_checker_results.csv" type: "csv" rewrite: false header: true; 
    	}       
	}		
}