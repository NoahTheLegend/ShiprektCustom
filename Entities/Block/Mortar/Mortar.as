#include "WeaponCommon.as";
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";
#include "ShipsCommon.as";

const f32 PROJECTILE_SPEED = 3.0f;
const f32 PROJECTILE_SPREAD = 0.4;
const int FIRE_RATE = 450; //30 is 1 second
const f32 PROJECTILE_RANGE = 300.0f;
const f32 CLONE_RADIUS = 20.0f;

// Max amount of ammunition
const uint8 MAX_AMMO = 8;

// Amount of ammunition to refill when
// connected to motherships and stations
const uint8 REFILL_AMOUNT = 1;

// How often to refill when connected
// to motherships and stations
const uint8 REFILL_SECONDS = 10;

// How often to refill when connected
// to secondary cores
const uint8 REFILL_SECONDARY_CORE_SECONDS = 15;

// Amount of ammunition to refill when
// connected to secondary cores
const uint8 REFILL_SECONDARY_CORE_AMOUNT = 1;

Random _shotspreadrandom(0x11598); //clientside

void onInit(CBlob@ this)
{
	this.Tag("mortar");
	this.Tag("weapon");
	this.Tag("usesAmmo");
	this.Tag("block");
	
	this.Tag("noEnemyEntry");
	this.set_string("seat label", "Control Mortar");
	this.set_u8("seat icon", 7);
	this.set_f32("distance", PROJECTILE_RANGE);
	
	this.set_f32("weight", 5.0f);
	
	this.addCommandID("fire");

	if (isServer())
	{
		this.set_u16("ammo", MAX_AMMO);
		this.set_u16("maxAmmo", MAX_AMMO);
		this.Sync("ammo", true);
		this.Sync("maxAmmo", true);
	}

	this.set_u32("fire time", 0);
	this.set_u16("parentID", 0);
	this.set_u16("childID", 0);

	CSprite@ sprite = this.getSprite();
    CSpriteLayer@ layer = sprite.addSpriteLayer("weapon", "Mortar.png", 16, 16);
    if (layer !is null)
    {
    	layer.SetRelativeZ(2);
    	layer.SetLighting(false);
     	Animation@ anim = layer.addAnimation("fire", 15, false);
        anim.AddFrame(1);
        anim.AddFrame(0);
        layer.SetAnimation("fire");
    }
}

void onTick(CBlob@ this)
{
	const int col = this.getShape().getVars().customData;
	if (col <= 0) return; //not placed yet

	u32 gameTime = getGameTime();
	AttachmentPoint@ seat = this.getAttachmentPoint(0);
	CBlob@ occupier = seat.getOccupied();
	u16 thisID = this.getNetworkID();
	u16 operatorid = 0;

	if (occupier !is null)
	{
		u32 gameTime = getGameTime();
		this.set_u16("parentID", 0);
		Manual(this, occupier);

		operatorid = occupier.getNetworkID();
		this.set_u16("operatorid", operatorid);

		CBlob@ childMortar = getBlobByNetworkID(this.get_u16("childID"));
		if (childMortar !is null)
		{
			if (!childMortar.hasAttached() && childMortar.getDistanceTo(this) < CLONE_RADIUS)
				Clone(childMortar, this, occupier);
			else
				this.set_u16("childID", 0);
		}
		else if (gameTime % 20 == 0)
		{
			@childMortar = findMortarChild(this);
			if (childMortar !is null)
			{
				this.set_u16("childID", childMortar.getNetworkID());
				childMortar.set_u16("parentID", thisID);
			}
		}
	}
	else if (this.get_u16("childID") != 0)//free child; parent
	{
		CBlob@ childMortar = getBlobByNetworkID(this.get_u16("childID"));
		if (childMortar !is null)
			childMortar.set_u16("parentID", 0);

		this.set_u16("childID", 0);
	}

	this.set_u16("operatorid", operatorid);

	if (isServer())
	{
		Ship@ ship = getShipSet().getShip(col);
		if (ship !is null)
		{
			checkDocked(this, ship);
			refillAmmo(this, ship, REFILL_AMOUNT, REFILL_SECONDS, REFILL_SECONDARY_CORE_AMOUNT, REFILL_SECONDARY_CORE_SECONDS);
		}
	}
}

void Manual(CBlob@ this, CBlob@ controller)
{
	const int col = this.getShape().getVars().customData;
	Vec2f aimpos = controller.getAimPos();
	Vec2f pos = this.getPosition();
	Vec2f aimVec = aimpos - pos;
	CPlayer@ player = controller.getPlayer();

	// fire
	if (controller.isMyPlayer() && controller.isKeyPressed(key_action1) && canShootManual(this))
	{
		Ship@ ship = getShipSet().getShip(col);
		u16 netID = 0;
		if (ship !is null && player !is null && (!ship.isMothership || ship.owner != player.getUsername()))
			netID = controller.getNetworkID();
		Fire(this, aimpos, netID);
	}

	// rotate turret
	Rotate(this, aimVec);
	aimVec.y *= -1;
	controller.setAngleDegrees(aimVec.Angle());
}

void Clone(CBlob@ this, CBlob@ parent, CBlob@ controller)
{
	Vec2f aimpos = controller.getAimPos();
	Vec2f pos = parent.getPosition();
	Vec2f aimVec = aimpos - pos;
	CPlayer@ player = controller.getPlayer();
	// fire
	if (getGameTime() - this.get_u32("fire time") > 50)//free it so it tries to find another
	{
		parent.set_u16("childID", 0);
		this.set_u16("parentID", 0);
	}
}

CBlob@ findMortarChild(CBlob@ this)
{
	int color = this.getShape().getVars().customData;
	CBlob@[] mortar;
	CBlob@[] radBlobs;
	getMap().getBlobsInRadius(this.getPosition(), CLONE_RADIUS, @radBlobs);
	for (uint i = 0; i < radBlobs.length; i++)
	{
		CBlob@ b = radBlobs[i];
		if (b.hasTag("mortar") && !b.hasAttached() && b.get_u16("parentID") == 0 && color == b.getShape().getVars().customData)
			mortar.push_back(b);
	}

	if (mortar.length > 0)
		return mortar[getGameTime() % mortar.length];

	return null;
}

bool canShootManual(CBlob@ this)
{
	return this.get_u32("fire time") + FIRE_RATE/2 < getGameTime();
}

void Fire(CBlob@ this, Vec2f aimpos, const u16 netid)
{
	Vec2f copy = aimpos-this.getPosition();
	const f32 aimdist = Maths::Min(copy.Normalize(), PROJECTILE_RANGE);

	Vec2f offset(_shotspreadrandom.NextFloat() * PROJECTILE_SPREAD,0);
	offset.RotateBy(_shotspreadrandom.NextFloat() * 360.0f, Vec2f());
	Vec2f tvel = (this.getPosition()-this.getOldPosition())*16;
	Vec2f _pos = aimpos+offset+tvel;

	f32 _lifetime = Maths::Max(0.05f + aimdist/PROJECTILE_SPEED/32.0f, 0.25f);

	CBitStream params;
	params.write_netid(netid);
	params.write_Vec2f(_pos);
	params.write_f32(_lifetime);
	this.SendCommand(this.getCommandID("fire"), params);
	this.set_u32("fire time", getGameTime());
}

void Rotate(CBlob@ this, Vec2f aimVector)
{
	CSpriteLayer@ layer = this.getSprite().getSpriteLayer("weapon");
	if (layer !is null)
	{
		layer.ResetTransform();
		layer.RotateBy(-aimVector.getAngleDegrees() - this.getAngleDegrees(), Vec2f_zero);
	}
}

void onCommand(CBlob@ this, u8 cmd, CBitStream@ params)
{
    if (cmd == this.getCommandID("fire"))
    {
		CBlob@ caller = getBlobByNetworkID(params.read_netid());
		Vec2f pos = this.getPosition();

		//ammo
		u16 ammo = this.get_u16("ammo");

		if (ammo == 0)
		{
			directionalSoundPlay("LoadingTick1", pos, 1.0f);
			return;
		}

		ammo--;
		this.set_u16("ammo", ammo);

		Vec2f projpos = params.read_Vec2f();
		Vec2f aimVector = projpos-this.getPosition();		aimVector.Normalize();
		const f32 time = params.read_f32();

		if (isServer())
		{
            CBlob@ bullet = server_CreateBlob("mortarbullet", this.getTeamNum(), pos + aimVector*9);
            if (bullet !is null)
            {
            	if (caller !is null)
                	bullet.SetDamageOwnerPlayer(caller.getPlayer());

                bullet.set_Vec2f("target", projpos);
				bullet.set_f32("vel", PROJECTILE_SPEED);

                bullet.server_SetTimeToDie(time);
				bullet.setAngleDegrees(-aimVector.Angle());
				bullet.set_f32("timeScaling", time);
            }
    	}

		if (isClient())
		{
			Rotate(this, aimVector);
			shotParticles(pos + aimVector*9, aimVector.Angle());
			directionalSoundPlay("MortarShoot.ogg", pos, 1.25f);

			CSpriteLayer@ layer = this.getSprite().getSpriteLayer("weapon");
			if (layer !is null)
				layer.animation.SetFrameIndex(0);
		}
    }
}
