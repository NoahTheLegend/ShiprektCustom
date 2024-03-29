#include "WeaponCommon.as";
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";

const f32 PROJECTILE_SPEED = 11.0f;
const f32 PROJECTILE_SPREAD = 16.0f;
const int FIRE_RATE = 45;
const f32 PROJECTILE_RANGE = 450.0f;
const f32 CLONE_RADIUS = 20.0f;
const f32 p1_lifetime = 1.5f;
const f32 p2_lifetime = 2.5f;

// Max amount of ammunition
const uint8 MAX_AMMO = 12;

// Amount of ammunition to refill when
// connected to motherships and stations
const uint8 REFILL_AMOUNT = 2;

// How often to refill when connected
// to motherships and stations
const uint8 REFILL_SECONDS = 6;
// How often to refill when connected
// to secondary cores
const uint8 REFILL_SECONDARY_CORE_SECONDS = 4;

// Amount of ammunition to refill when
// connected to secondary cores
const uint8 REFILL_SECONDARY_CORE_AMOUNT = 1;

void onInit(CBlob@ this)
{
	this.Tag("hyperflak");
	this.Tag("weapon");
	this.Tag("usesAmmo");
	this.Tag("block");
	
	this.set_u16("cost", 300);
	this.set_f32("weight", 3.5f);
	
	this.addCommandID("fire1");
	this.addCommandID("fire2");
	this.addCommandID("clear attached");

	if (isServer())
	{
		this.set_u16("ammo", MAX_AMMO);
		this.set_u16("maxAmmo", MAX_AMMO);
		this.Sync("ammo", true);
		this.Sync("maxAmmo", true);
		
		this.set_bool("seatEnabled", true);
		this.Sync("seatEnabled", true);
	}

	this.set_u32("fire time", 0);
	this.set_u16("parentID", 0);
	this.set_u16("childID", 0);

	CSprite@ sprite = this.getSprite();
    CSpriteLayer@ layer = sprite.addSpriteLayer("weapon", "Hammer.png", 16, 16);
    if (layer !is null)
    {
		layer.SetOffset(Vec2f(-4, 0));
    	layer.SetRelativeZ(2);
    	layer.SetLighting(false);
     	Animation@ anim = layer.addAnimation("fire", 19, false);
        anim.AddFrame(1);
        anim.AddFrame(0);
        layer.SetAnimation("fire");
    }
}

void onTick(CBlob@ this)
{
	const int col = this.getShape().getVars().customData;

	if (col <= 0)
		return;

	u32 gameTime = getGameTime();
	AttachmentPoint@ seat = this.getAttachmentPoint(0);
	CBlob@ occupier = seat.getOccupied();
	u16 thisID = this.getNetworkID();
	if ( occupier !is null )
	{
		u32 gameTime = getGameTime();
		this.set_u16("parentID", 0);
		Manual(this, occupier);

		//owned repulsors managing
		if (occupier.isKeyJustPressed(key_action3))
		{
			CPlayer@ player = occupier.getPlayer();
			if (player !is null)
			{
				string occupierName = player.getUsername();
				CBlob@[] repulsors;
				getBlobsByTag( "repulsor", @repulsors );
				for (uint i = 0; i < repulsors.length; ++i)
				{
					CBlob@ r = repulsors[i];
					if (r.getShape().getVars().customData > 0 && r.isOnScreen() && !r.hasTag("activated" ) && r.get_string("playerOwner") == occupierName)
					{
						CButton@ button = occupier.CreateGenericButton(8, Vec2f(0.0f, 0.0f), r, r.getCommandID("chainReaction"), "Activate");

						if (button !is null)
						{
							button.enableRadius = 999.0f;
							button.radius = 3.3f; //engine fix
						}
					}
				}
			}
		}
		else if (occupier.isKeyJustReleased(key_action3))
			occupier.ClearButtons();
	}

	if (isServer())
	{
		Ship@ ship = getShipSet().getShip(col);
		if (ship !is null)
			refillAmmo(this, ship, REFILL_AMOUNT, REFILL_SECONDS, REFILL_SECONDARY_CORE_AMOUNT, REFILL_SECONDARY_CORE_SECONDS);
	}
}

void Manual(CBlob@ this, CBlob@ controller)
{
	Vec2f aimpos = controller.getAimPos();
	Vec2f pos = this.getPosition();
	Vec2f aimVec = aimpos - pos;
	CPlayer@ player = controller.getPlayer();

	// fire
	if (controller.isMyPlayer() && controller.isKeyPressed(key_action1) && canShootManual(this))
	{
		u16 netID = 0;
		if (player !is null)
			netID = controller.getNetworkID();
		Fire1(this, aimVec, netID);
	}

	if ( controller.isMyPlayer() && controller.isKeyPressed(key_action2) && canShootManual2(this))
	{
		u16 netID = 0;
		if (player !is null)
			netID = controller.getNetworkID();
		Fire2(this, aimVec, netID);
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
	if (isClearShot(this, aimVec))
	{
		Rotate(this, aimVec);
		if (controller.isMyPlayer() && controller.isKeyPressed(key_action1) && canShootManual(this) && (getGameTime() - parent.get_u32("fire time") == FIRE_RATE))
		{
			u16 netID = 0;
			if (player !is null)
				netID = controller.getNetworkID();
			Fire1(this, aimVec, netID);
		}
	}
}

bool canShootManual(CBlob@ this)
{
	return this.get_u32("fire time") + FIRE_RATE < getGameTime();
}

bool canShootManual2(CBlob@ this)
{
	return this.get_u32("fire time") + FIRE_RATE*2.5f < getGameTime();
}

bool isClearShot(CBlob@ this, Vec2f aimVec, bool targetMerged = false)
{
	Vec2f pos = this.getPosition();
	const f32 distanceToTarget = Maths::Max(aimVec.Length(), 80.0f);
	HitInfo@[] hitInfos;
	CMap@ map = getMap();

	Vec2f offset = aimVec;
	offset.Normalize();
	offset *= 7.0f;

	map.getHitInfosFromRay(pos + offset.RotateBy(30), -aimVec.Angle(), distanceToTarget, this, @hitInfos);
	map.getHitInfosFromRay(pos + offset.RotateBy(-60), -aimVec.Angle(), distanceToTarget, this, @hitInfos);
	if (hitInfos.length > 0)
	{
		//HitInfo objects are sorted, first come closest hits
		for (uint i = 0; i < hitInfos.length; i++)
		{
			HitInfo@ hi = hitInfos[i];
			CBlob@ b = hi.blob;
			if (b is null || b is this) continue;

			int thisColor = this.getShape().getVars().customData;
			int bColor = b.getShape().getVars().customData;
			bool sameIsland = bColor != 0 && thisColor == bColor;

			bool canShootSelf = targetMerged && hi.distance > distanceToTarget * 0.7f;

			//if (sameIsland || targetMerged) print ("" + (sameIsland ? "sameisland; " : "") + (targetMerged ? "targetMerged; " : ""));

			if (b.hasTag("block") && b.getShape().getVars().customData > 0 && (b.hasTag("solid") || b.hasTag("weapon")) && sameIsland && !canShootSelf)
			{
				//print ("not clear " + (b.hasTag("block") ? " (block) " : "") + (!canShootSelf ? "!canShootSelf; " : ""));
				return false;
			}
		}
	}

	Vec2f solidPos;
	if (map.rayCastSolid(pos, pos + aimVec, solidPos))
	{
		AttachmentPoint@ seat = this.getAttachmentPoint(0);
		CBlob@ occupier = seat.getOccupied();

		if (occupier is null)
			return false;
	}

	return true;
}

void Fire1(CBlob@ this, Vec2f aimVector, const u16 netid)
{
	const f32 aimdist = Maths::Min(aimVector.Normalize(), PROJECTILE_RANGE);

	//Vec2f offset(PROJECTILE_SPREAD,0);
	//offset.RotateBy(360.0f, Vec2f());

	Vec2f _vel = (aimVector * PROJECTILE_SPEED/1.25f);// + offset;

	f32 _lifetime = Maths::Max( 0.05f + aimdist/PROJECTILE_SPEED/32.0f, 0.25f);

	CBitStream params;
	params.write_netid(netid);
	params.write_Vec2f(_vel);
	params.write_f32(_lifetime);
	this.SendCommand(this.getCommandID("fire1"), params);
	this.set_u32("fire time", getGameTime());
}

void Fire2( CBlob@ this, Vec2f aimVector, const u16 netid)
{
	const f32 aimdist = Maths::Min(aimVector.Normalize(), PROJECTILE_RANGE);

	//Vec2f offset(PROJECTILE_SPREAD,0);
	//offset.RotateBy(360.0f, Vec2f());

	Vec2f _vel = (aimVector * PROJECTILE_SPEED/2.5f);// + offset;

	f32 _lifetime = Maths::Max(0.05f + aimdist/PROJECTILE_SPEED/32.0f, 0.25f);

	CBitStream params;
	params.write_netid(netid);
	params.write_Vec2f(_vel);
	params.write_f32(_lifetime);
	this.SendCommand(this.getCommandID("fire2"), params);
	this.set_u32("fire time", getGameTime());
}

void Rotate(CBlob@ this, Vec2f aimVector)
{
	CSpriteLayer@ layer = this.getSprite().getSpriteLayer("weapon");
	if (layer !is null)
	{
		layer.ResetTransform();
		layer.RotateBy(-aimVector.getAngleDegrees() - this.getAngleDegrees(), Vec2f(4,0));
	}
}

void GetButtonsFor(CBlob@ this, CBlob@ caller)
{
	if (this.getDistanceTo(caller) > 6
		|| this.getShape().getVars().customData <= 0
		|| this.hasAttached()
		|| this.getTeamNum() != caller.getTeamNum())
		return;

	CBitStream params;
	params.write_u16( caller.getNetworkID() );

	CButton@ button = caller.CreateGenericButton(7, Vec2f(0.0f, 0.0f), this, this.getCommandID("get in seat"), "Control Hammer", params );
	if (button !is null) button.radius = 3.3f; //engine fix
}

void onCommand(CBlob@ this, u8 cmd, CBitStream @params)
{
    if (cmd == this.getCommandID("fire1"))
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

		Vec2f velocity = params.read_Vec2f();
		Vec2f aimVector = velocity;	aimVector.Normalize();
		const f32 time = params.read_f32();

		if (isServer())
		{
            CBlob@ bullet = server_CreateBlob("hammerbullet", this.getTeamNum(), pos + aimVector*9);
            if (bullet !is null)
            {
            	if (caller !is null)
                	bullet.SetDamageOwnerPlayer(caller.getPlayer());

                bullet.setVelocity(velocity);
                bullet.server_SetTimeToDie(p1_lifetime);
				bullet.set_u32("color", this.getShape().getVars().customData);
				bullet.setAngleDegrees(-aimVector.Angle());
            }
    	}

		Rotate(this, aimVector);
		shotParticles(pos + aimVector*9, velocity.Angle());
		directionalSoundPlay("HyperFlakFire1.ogg", pos, 1.0f);

		CSpriteLayer@ layer = this.getSprite().getSpriteLayer("weapon");
		if (layer !is null)
			layer.animation.SetFrameIndex(0);
    }
	else if (cmd == this.getCommandID("fire2"))
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

		Vec2f velocity = params.read_Vec2f();
		Vec2f aimVector = velocity;	aimVector.Normalize();
		const f32 time = params.read_f32();

		if (isServer())
		{
            CBlob@ bullet = server_CreateBlob("hammerbulletsecondary", this.getTeamNum(), pos + aimVector*9);
            if (bullet !is null)
            {
            	if (caller !is null)
                	bullet.SetDamageOwnerPlayer(caller.getPlayer());

                bullet.setVelocity(velocity);
                bullet.server_SetTimeToDie(p2_lifetime);
				bullet.set_u32("color", this.getShape().getVars().customData);
				bullet.setAngleDegrees(-aimVector.Angle());
            }
    	}

		Rotate(this, aimVector);
		shotParticles(pos + aimVector*9, velocity.Angle());
		directionalSoundPlay("HyperFlakFire2.ogg", pos, 1.0f);

		CSpriteLayer@ layer = this.getSprite().getSpriteLayer("weapon");
		if (layer !is null)
			layer.animation.SetFrameIndex(0);
    }
	else if (cmd == this.getCommandID("clear attached"))
	{
		AttachmentPoint@ seat = this.getAttachmentPoint(0);
		CBlob@ crewmate = seat.getOccupied();
		if (crewmate !is null)
			crewmate.SendCommand(crewmate.getCommandID("get out"));
	}
}