
#include "AccurateSoundPlay.as";
void onInit(CBlob@ this)
{
	//this.addCommandID("couple");
	this.Tag("loader");
	//this.Tag("couples");
    this.Tag("solid");
	this.Tag("no reward");
	
	this.set_f32("extra reclaim time", 12.5f);
	this.set_f32("weight", 10.0f);
}

/*void onCommand(CBlob@ this, u8 cmd, CBitStream@ params)
{
	if (cmd == this.getCommandID("couple"))
	{
		if (isClient())
		{
			directionalSoundPlay("mechanical_click", this.getPosition());
		}
		if (isServer())
		{
			CBlob@[] tempArray; tempArray.push_back(this);
			getRules().push("dirtyBlocks", tempArray);
		}
	}
}*/