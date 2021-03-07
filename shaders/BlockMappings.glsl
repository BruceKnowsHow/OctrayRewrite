#if MC_VERSION >= 11300
	int backport_id(int ID) {
		if (ID == -1) return 1; // un-assigned blocks in 1.13+
		
		return ID;
	}
#else
	int backport_id(int ID) {
		return ID;
	}
#endif

#if (defined gbuffers_entities)
	#define backport_id(ID) 0
#endif


#define UNHANDLED_BLOCKS 1  // [0 1 2]

bool is_entity(int ID)        { return ID == 0; }
bool is_simple_voxel(int ID)  { return ID == 2; }
bool is_leaves_type(int ID)   { return (ID % 64) == 3; }
bool is_glass_type(int ID)    { return (ID % 64) == 4; }
bool is_emissive(int ID)      { return (ID & 64) > 0 && (ID != 250); }
bool is_water(int ID)         { return ID == 21; }
bool is_backface_type(int ID) { return ID == 3 || ID == 4; }
bool is_sapling(int ID)       { return ID == 5; }
bool is_tallgrass(int ID)     { return ID == 7; }
bool is_sub_voxel(int ID)     { return ID >= 3 && ID <= 13; }
bool is_voxelized(int ID)     { return is_sub_voxel(ID) || (!is_entity(ID)) && (ID != 1) && (ID < 5 || ID == 8 || ID == 66 || ID >= 85 || ID == 75) && (ID != 250); }
